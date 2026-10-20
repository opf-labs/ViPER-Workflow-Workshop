#!/usr/bin/env bash
#
# Adds the iPRES 2026 workshop tooling to a ViPER 2.0.0-alpha virtual machine:
# Node-RED with the OPF preservation palette, the ViPER Assistant, the dp-run runner,
# the demo flows, the notebooks and the teaching corpus.
#
# ViPER already ships the preservation tools. This script adds the workflow and
# assistant layer that was demonstrated at the workshop, which lived in a separate
# Docker image and is not part of ViPER itself.
#
# Run it as the ordinary desktop user, not with sudo. It will ask for your password
# when it needs root.
#
#     ./install.sh                 install everything
#     ./install.sh --check         report what would change, touch nothing
#     ./install.sh --minimal       Node-RED and the Assistant only, no corpus or notebooks
#
# Safe to run twice. Anything already present is left alone.

set -euo pipefail

# Where the workshop files come from.
#
# This script is meant to be shareable on its own, as a gist: a participant downloads
# one file in the ViPER browser and runs it. So it fetches its own payload rather than
# expecting a tarball unpacked beside it. If a payload directory IS next to the script,
# that wins, which is what makes offline and development use work unchanged.
#
# MAINTAINER: set this to wherever the tarball is published before sharing the gist.
PAYLOAD_URL="${PAYLOAD_URL:-https://raw.githubusercontent.com/opf-labs/ViPER-Workflow-Workshop/main/viper-workshop-extras.tar.gz}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo /tmp)"
PAYLOAD_DIR="${SCRIPT_DIR}/payload"
DOWNLOAD_TMP=""
cleanup() { [ -n "${DOWNLOAD_TMP}" ] && rm -rf "${DOWNLOAD_TMP}"; }
trap cleanup EXIT
PREFIX=/opt/workshop
# Where flows write reports and converted files, and where the corpus is linked.
# Resolved in preflight once the directory is known to exist, because deciding it up
# front picked $HOME on a machine whose Desktop had not been created yet.
OUTPUT_DIR=""
NODE_MAJOR=22
# The version demonstrated at the workshop. Pinned so participants get what they saw.
OPENCODE_VERSION=1.18.31
OPENCODE_HOME=/opt/opencode
JUPYTER_HOME=/opt/jupyter
SIEGFRIED_VERSION=1.11.7

CHECK_ONLY=false
MINIMAL=false
for arg in "$@"; do
    case "${arg}" in
        --check)   CHECK_ONLY=true ;;
        --minimal) MINIMAL=true ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: ${arg}" >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33mwarning:\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    if ${CHECK_ONLY}; then
        info "would run: $*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------- preflight

say "Checking this machine"

[ "$(id -u)" -ne 0 ] || die "Do not run this with sudo. Run it as your normal desktop
       user; it will ask for a password when it needs root. Running as root would
       install the flows and the assistant config into /root instead of your home."

command -v sudo >/dev/null 2>&1 || die "sudo is not installed, so this cannot install packages."

# Ask for the password once, here, rather than letting sudo prompt from the middle of
# an apt run where it reads like something has gone wrong. On ViPER the account is
# 'viper' and the password is documented with the image.
if ! ${CHECK_ONLY} && ! sudo -n true 2>/dev/null; then
    echo
    echo "    Parts of this need administrator rights, so sudo will ask for your"
    echo "    password now. On a stock ViPER machine that is the password documented"
    echo "    with the image for the 'viper' account."
    echo
    sudo -v || die "Could not authenticate with sudo, so nothing has been changed.
       If you do not know the password for this machine, check the ViPER setup guide
       at https://viper.openpreservation.org/setup/"
fi
command -v apt-get >/dev/null 2>&1 || die "This expects a Debian or Ubuntu system, which is what ViPER is built on."

if [ ! -d "${PAYLOAD_DIR}/opt/workshop" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is needed to fetch the workshop files."
    info "payload         not found locally, downloading"
    info "from            ${PAYLOAD_URL}"
    DOWNLOAD_TMP="$(mktemp -d)"
    curl -fL --progress-bar -o "${DOWNLOAD_TMP}/payload.tar.gz" "${PAYLOAD_URL}" \
        || die "Could not download the workshop files from
       ${PAYLOAD_URL}
       Check that this machine has internet access, then try again."
    tar -xzf "${DOWNLOAD_TMP}/payload.tar.gz" -C "${DOWNLOAD_TMP}" \
        || die "The downloaded file is not a readable archive. It may be incomplete."
    # Tolerate the tarball having a top-level directory or not.
    if [ -d "${DOWNLOAD_TMP}/payload/opt/workshop" ]; then
        PAYLOAD_DIR="${DOWNLOAD_TMP}/payload"
    else
        # Depth 5, not 3: the tarball has a top-level directory, so the path is
        # <tmp>/viper-workshop-extras/payload/opt/workshop, which is four levels down.
        found="$(find "${DOWNLOAD_TMP}" -maxdepth 5 -type d -path '*/payload/opt/workshop' -print -quit)"
        [ -n "${found}" ] || die "The archive did not contain the expected payload/opt/workshop."
        PAYLOAD_DIR="$(dirname "$(dirname "${found}")")"
    fi
fi

# ViPER is a desktop, and so is the container's /config, so output belongs on the
# Desktop where a participant will actually find it. Created if absent rather than
# silently falling back, which is what hid the corpus link on the first test run.
mkdir -p "${HOME}/Desktop" 2>/dev/null || true
OUTPUT_DIR="${HOME}/Desktop"
[ -d "${OUTPUT_DIR}" ] || OUTPUT_DIR="${HOME}"

# opencode is built on Bun, which segfaults on a CPU without AVX rather than failing
# cleanly. Seen while testing under QEMU with a generic virtual CPU: a wall of Bun
# crash output and a bun.report URL, with nothing naming the real cause. VirtualBox
# normally passes AVX through from the host, so most people will never see this.
HAVE_AVX=true
grep -qw avx /proc/cpuinfo 2>/dev/null || HAVE_AVX=false

info "user            ${USER}"
info "home            ${HOME}"
info "output to       ${OUTPUT_DIR}"
info "payload         ${PAYLOAD_DIR}"
${CHECK_ONLY} && warn "check mode, nothing will be changed"

# ViPER's own tools. We do not install these; we report them so that a missing one
# explains itself later rather than surfacing as a confusing dp-run error.
say "Preservation tools already provided by ViPER"
MISSING_TOOLS=()
for t in fido droid jhove verapdf jpylyzer mediainfo mediaconch exiftool ocrmypdf odf-validator; do
    if command -v "${t}" >/dev/null 2>&1; then
        printf '    %-16s %s\n' "${t}" "$(command -v "${t}")"
    else
        printf '    %-16s \033[33mnot found\033[0m\n' "${t}"
        MISSING_TOOLS+=("${t}")
    fi
done
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    warn "${#MISSING_TOOLS[@]} tool(s) not found: ${MISSING_TOOLS[*]}"
    warn "Those steps of the demo flows will report 'tool not available'."
    warn "Everything else still works. This is not fatal."
fi

# ------------------------------------------------------- python for dp-run

# dp-run is Python and needs PyYAML to read the tool manifests. In the Docker image it
# runs on a bundled interpreter at /lsiopy/bin/python3 that already has it; on a VM we
# use the system python3 and install the module from apt rather than pip, so it is
# managed and does not need --break-system-packages.
say "Python support for the dp-run tool runner"
command -v python3 >/dev/null 2>&1 || die "python3 not found, which is unexpected on ViPER."
PYTHON_BIN="$(command -v python3)"
info "interpreter     ${PYTHON_BIN}"
if "${PYTHON_BIN}" -c 'import yaml' 2>/dev/null; then
    info "PyYAML          already present"
else
    info "PyYAML          installing python3-yaml"
    run sudo apt-get update -qq
    run sudo apt-get install -y python3-yaml
fi

# ------------------------------------------------------------------ node.js

if ! ${HAVE_AVX}; then
    warn "This machine's CPU does not report AVX support."
    warn "Node-RED and all the preservation tools will work normally."
    warn "The ViPER Assistant will NOT: it crashes on startup without AVX, with a"
    warn "long Bun crash report that does not explain why. If this is a virtual"
    warn "machine, check that the hypervisor is passing CPU features through."
fi

say "Node.js, for Node-RED and the Assistant"
NEED_NODE=true
if command -v node >/dev/null 2>&1; then
    current="$(node -v | sed 's/^v//; s/\..*//')"
    if [ "${current}" -ge 20 ] 2>/dev/null; then
        info "node            $(node -v), new enough"
        NEED_NODE=false
    else
        warn "node $(node -v) is too old; Node-RED and opencode need 20 or newer"
    fi
fi

if ${NEED_NODE}; then
    info "installing Node.js ${NODE_MAJOR}.x from nodesource"
    if ${CHECK_ONLY}; then
        info "would run: nodesource setup script, then apt-get install nodejs"
    else
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
fi

say "Node-RED and the ViPER Assistant runtime"
if command -v node-red >/dev/null 2>&1; then
    info "node-red        already installed ($(node-red --help 2>/dev/null | head -1 || echo present))"
else
    run sudo npm install -g --omit=dev node-red
fi
# NOT `npm install -g opencode-ai`, which is what the workshop image uses and what you
# would reach for first. On this VM it fails: npm resolves the package's MUSL binary on
# a glibc system and the postinstall aborts with EBADPLATFORM, leaving a wrapper that
# errors on every run. Pinning the version, --omit=optional and --libc=glibc all still
# fail, because the postinstall itself insists on the musl packages.
#
# The official installer picks the right binary for the platform. It hardcodes
# INSTALL_DIR to $HOME/.opencode/bin, so HOME is pointed at a system location and the
# binary symlinked onto PATH, which also keeps it shared between users rather than
# landing in whoever ran the installer's home directory.
if command -v opencode >/dev/null 2>&1 && opencode --version >/dev/null 2>&1; then
    info "opencode        already installed ($(opencode --version 2>/dev/null))"
elif ${CHECK_ONLY}; then
    info "would install opencode ${OPENCODE_VERSION} to ${OPENCODE_HOME}"
else
    sudo mkdir -p "${OPENCODE_HOME}"
    if sudo env HOME="${OPENCODE_HOME}" VERSION="${OPENCODE_VERSION}" \
            bash -c 'curl -fsSL https://opencode.ai/install | bash' >/dev/null 2>&1 \
       && [ -x "${OPENCODE_HOME}/.opencode/bin/opencode" ]; then
        sudo ln -sfn "${OPENCODE_HOME}/.opencode/bin/opencode" /usr/local/bin/opencode
        info "opencode        $(opencode --version 2>/dev/null || echo installed)"
    else
        warn "opencode could not be installed. Node-RED and the tools are unaffected;"
        warn "only the ViPER Assistant will be missing. Try again later, or report it."
    fi
fi

# --------------------------------------------------------------- siegfried

# Not part of ViPER, and flow 2 compares it against fido and DROID. The signature file
# is taken from the release's own data archive rather than `sf -update`, which pins it
# to the same tag as the binary.
if ! ${MINIMAL}; then
    say "Siegfried, used by the 'compare identifiers' flow"
    if command -v sf >/dev/null 2>&1; then
        info "sf              already installed"
    elif ${CHECK_ONLY}; then
        info "would download and install siegfried ${SIEGFRIED_VERSION}"
    else
        ver_path="${SIEGFRIED_VERSION//./-}"
        tmp="$(mktemp -d)"
        if curl -fsSL -o "${tmp}/sf.zip" \
            "https://github.com/richardlehane/siegfried/releases/download/v${SIEGFRIED_VERSION}/siegfried_${ver_path}_linux64_static.zip" \
           && curl -fsSL -o "${tmp}/data.zip" \
            "https://github.com/richardlehane/siegfried/releases/download/v${SIEGFRIED_VERSION}/data_${ver_path}.zip"; then
            command -v unzip >/dev/null 2>&1 || sudo apt-get install -y unzip
            unzip -o -q "${tmp}/sf.zip" -d "${tmp}/bin"
            unzip -o -q "${tmp}/data.zip" siegfried/default.sig -d "${tmp}/sig"
            sudo install -m 0755 "${tmp}/bin/sf" /usr/local/bin/sf
            sudo mkdir -p /usr/share/siegfried
            sudo install -m 0644 "${tmp}/sig/siegfried/default.sig" /usr/share/siegfried/default.sig
            info "sf              $(sf -version | head -1)"
        else
            warn "could not download siegfried; skipping. Flow 2 will show it as unavailable."
        fi
        rm -rf "${tmp}"
    fi
fi

# --------------------------------------------------------------- jupyterlab

# ViPER has no JupyterLab, so the Notebooks launcher reports "not installed in this
# image" and stops. Installed into its own virtualenv rather than the system Python:
# Ubuntu 26.04 marks the system interpreter externally managed (PEP 668), so a plain
# pip install refuses, and --break-system-packages would put workshop packages in the
# same place as ViPER's own tooling.
#
# tornado is pinned and has to be. 6.5 added a symlink check to its static file handler
# that rejects JupyterLab's own symlinked assets, and the Lab UI loads to a blank page
# with no error anywhere. nbconvert still works, so automated checks pass. Found from a
# live desktop on 2026-09-15 after days of green builds.
if ! ${MINIMAL}; then
    say "JupyterLab, for the notebook versions of the exercises"
    if command -v jupyter >/dev/null 2>&1; then
        info "jupyter         already installed"
    elif ${CHECK_ONLY}; then
        info "would create a virtualenv at ${JUPYTER_HOME} with jupyterlab, pandas, tornado 6.4.2"
    else
        # Test ensurepip, NOT venv. On Ubuntu the venv module always imports, while
        # ensurepip ships separately in python3-venv, so checking `import venv` passes
        # and `python3 -m venv` then fails with "Failing command: .../bin/python3".
        if ! python3 -c 'import ensurepip' 2>/dev/null; then
            info "venv support    installing python3-venv"
            sudo apt-get update -qq
            sudo apt-get install -y python3-venv
        fi
        sudo mkdir -p "${JUPYTER_HOME}"
        if sudo python3 -m venv "${JUPYTER_HOME}" \
           && sudo "${JUPYTER_HOME}/bin/pip" install --quiet --no-cache-dir \
                jupyterlab pandas "tornado==6.4.2"; then
            for b in "${JUPYTER_HOME}"/bin/jupyter*; do
                [ -x "${b}" ] && sudo ln -sfn "${b}" "/usr/local/bin/$(basename "${b}")"
            done
            ver="$(sudo "${JUPYTER_HOME}/bin/python" -c 'import tornado,jupyterlab; print("jupyterlab", jupyterlab.__version__, "tornado", tornado.version)' 2>/dev/null)"
            info "jupyter         ${ver:-installed}"
        else
            warn "JupyterLab could not be installed. Everything else is unaffected;"
            warn "only the ViPER Notebooks launcher will be missing."
        fi
    fi
fi

# ----------------------------------------------------------------- payload

say "Installing the workshop files to ${PREFIX}"
if ${CHECK_ONLY}; then
    info "would copy $(du -sh "${PAYLOAD_DIR}/opt/workshop" | cut -f1) to ${PREFIX}"
else
    sudo mkdir -p "${PREFIX}"
    sudo cp -a "${PAYLOAD_DIR}/opt/workshop/." "${PREFIX}/"
    sudo chmod -R a+rX "${PREFIX}"
    sudo chmod 755 "${PREFIX}"/bin/*
    info "copied          $(find "${PREFIX}" -type f | wc -l) files"
fi

# The runner's shebang points at the Docker image's bundled interpreter, which does not
# exist on a VM. Repoint it at whichever python3 we checked above.
say "Adapting the files for a virtual machine"
if ${CHECK_ONLY}; then
    info "would repoint the dp-run shebang at ${PYTHON_BIN}"
    info "would rewrite /config paths to ${HOME}"
else
    sudo sed -i "1s|^#!.*|#!${PYTHON_BIN}|" "${PREFIX}/bin/dp-run"
    info "dp-run          shebang now ${PYTHON_BIN}"

    # In the container, /config IS the user's home directory, and it is where the
    # desktop, the flows and the assistant's scratchpad live. On a VM that is $HOME.
    for f in "${PREFIX}"/bin/* "${PREFIX}"/agent/AGENTS.md; do
        [ -f "${f}" ] && sudo sed -i "s|/config/|${HOME}/|g; s|\"/config\"|\"${HOME}\"|g; s|=/config$|=${HOME}|g" "${f}"
    done
    info "launchers       /config rewritten to ${HOME}"

    # The flows point at the JHOVE test corpora, which the workshop server mounted and
    # neither a VM nor a plain container has. Repoint them at the teaching corpus.
    #
    # Deliberately at the SYSTEM path /opt/workshop/corpus, not at a copy in someone's
    # home directory. That one choice makes the flows portable: the same flows.json
    # works in the Docker image, on the VM, and for every user on a shared machine,
    # with no per-user rewriting and nothing to re-run when a second person logs in.
    CORPUS="${PREFIX}/corpus"
    for f in "${PREFIX}"/node-red/flows.json "${PREFIX}"/flows/*.json "${PREFIX}"/notebooks/*.ipynb; do
        [ -f "${f}" ] || continue
        # '#' as the delimiter, not '|'. These paths contain no '#', and using '|'
        # here silently broke the PDF-hul rules: sed read the '\|' alternation as an
        # escaped delimiter, so the rule never matched and the generic rule below
        # rewrote the prefix only, leaving paths like
        # .../batch-folder/examples/modules/PDF-hul. Caught by running the installer.
        #
        # Most specific first: each rule below would otherwise be swallowed by the
        # bare /config/test-corpus rule that follows it.
        sudo sed -i \
            -e "s#/config/test-corpus/examples/modules/TIFF-hul/ddap#${CORPUS}/01-identification/batch-folder#g" \
            -e "s#/config/test-corpus/examples/modules/WAVE-hul#${CORPUS}/03-characterization#g" \
            -e "s#/config/test-corpus/errors/modules/PDF-hul#${CORPUS}/02-validation#g" \
            -e "s#/config/test-corpus/examples/modules/PDF-hul#${CORPUS}/02-validation#g" \
            -e "s#/config/test-corpus#${CORPUS}/01-identification/batch-folder#g" \
            -e "s#/config/Desktop/workshop-corpus#${CORPUS}#g" \
            -e "s#/config/Desktop#${OUTPUT_DIR}#g" \
            -e "s#/config/#${HOME}/#g" \
            "${f}"
    done
    info "flows           read from ${CORPUS}, write to ${OUTPUT_DIR}"
fi

say "Putting the commands on your PATH"
# In check mode /opt/workshop does not exist yet, so look in the payload instead or the
# section prints nothing and reads like a failure.
SRC_BIN="${PREFIX}/bin"
${CHECK_ONLY} && SRC_BIN="${PAYLOAD_DIR}/opt/workshop/bin"
for cmd in dp-run dp-signatures dp-search viper-workflows viper-notebooks viper-assistant; do
    [ -f "${SRC_BIN}/${cmd}" ] || continue
    run sudo ln -sfn "${PREFIX}/bin/${cmd}" "/usr/local/bin/${cmd}"
done
${CHECK_ONLY} || info "linked          $(ls "${PREFIX}/bin" | wc -l) commands into /usr/local/bin"

# ------------------------------------------------------ node-red as a service

# In the Docker image Node-RED runs under s6. A VM has systemd, and a *user* unit is the
# right equivalent: it runs as you, with your home directory, and starts when you log in.
say "Node-RED service"
UNIT_DIR="${HOME}/.config/systemd/user"
if ${CHECK_ONLY}; then
    info "would write ${UNIT_DIR}/node-red.service and enable it"
else
    mkdir -p "${UNIT_DIR}" "${HOME}/.node-red"
    for seed in settings.js flows.json; do
        if [ -f "${PREFIX}/node-red/${seed}" ] && [ ! -f "${HOME}/.node-red/${seed}" ]; then
            cp "${PREFIX}/node-red/${seed}" "${HOME}/.node-red/${seed}"
            info "seeded          ${seed}"
        else
            info "kept            ${seed} (already present, your edits are safe)"
        fi
    done

    # nodesDir makes Node-RED load the OPF palette straight from /opt/workshop, so the
    # nodes never need installing into the user directory.
    sed -i "s|/opt/workshop/node-red/nodes|${PREFIX}/node-red/nodes|" "${HOME}/.node-red/settings.js" 2>/dev/null || true

    cat > "${UNIT_DIR}/node-red.service" <<EOF
[Unit]
Description=Node-RED for the iPRES 2026 preservation workshop
After=network.target

[Service]
Type=simple
ExecStart=$(command -v node-red) --userDir ${HOME}/.node-red --settings ${HOME}/.node-red/settings.js --port 1880 --no-telemetry
Restart=on-failure
RestartSec=5
WorkingDirectory=${HOME}

[Install]
WantedBy=default.target
EOF
    if systemctl --user daemon-reload 2>/dev/null \
       && systemctl --user enable --now node-red.service 2>/dev/null; then
        info "service         node-red.service enabled and started"
        # Without this the service only runs while you are logged in graphically.
        sudo loginctl enable-linger "${USER}" 2>/dev/null \
            || warn "could not enable linger; Node-RED will start when you log in"
    else
        # No session bus. Happens over SSH and in containers. The unit file is written
        # either way, so this is recoverable from the desktop without rerunning.
        warn "could not talk to your systemd user session, so Node-RED was not started."
        warn "The service file is written. From a terminal ON THE DESKTOP, run:"
        warn "    systemctl --user enable --now node-red"
        warn "Or start it by hand with:  node-red --userDir ${HOME}/.node-red"
    fi
fi

# --------------------------------------------------------------- desktop

say "Launcher icons"
# The .desktop files reference icons by bare name (Icon=node-red), so the PNGs have to
# be installed where the icon theme looks or every launcher falls back to a blank page
# icon. The images ship in the payload; the Docker image symlinks them into
# /usr/share/icons and this does the same.
if ${CHECK_ONLY}; then
    info "would install $(ls "${PAYLOAD_DIR}/opt/workshop/icons"/*.png 2>/dev/null | wc -l) icons to /usr/share/icons"
else
    n=0
    for icon in "${PREFIX}"/icons/*.png; do
        [ -f "${icon}" ] || continue
        sudo install -m 0644 "${icon}" "/usr/share/icons/$(basename "${icon}")"
        n=$((n+1))
    done
    # Without this MATE keeps serving the cached miss and the icons stay blank until
    # the next login, which reads as "the installer did not work".
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
    info "installed       ${n} icons to /usr/share/icons"
fi

say "Desktop launchers"
if ${CHECK_ONLY}; then
    info "would install .desktop files for Workflows, Notebooks and the Assistant"
else
    mkdir -p "${HOME}/Desktop" "${HOME}/.local/share/applications"
    for d in "${PREFIX}"/desktop/*.desktop; do
        [ -f "${d}" ] || continue
        name="$(basename "${d}")"
        sed "s|/config/|${HOME}/|g" "${d}" > "${HOME}/.local/share/applications/${name}"
        cp "${HOME}/.local/share/applications/${name}" "${HOME}/Desktop/${name}"
        chmod +x "${HOME}/Desktop/${name}"
        # Caja and the other MATE file managers refuse to run a launcher they do not
        # trust, and show the raw file instead, which looks like the icon is broken.
        gio set "${HOME}/Desktop/${name}" metadata::trusted true 2>/dev/null || true
    done
    info "installed       $(ls "${PREFIX}/desktop"/*.desktop 2>/dev/null | wc -l) launchers"
fi

# ---------------------------------------------------------------- corpus

if ! ${MINIMAL}; then
    say "Teaching corpus"
    info "installed at    ${PREFIX}/corpus (shared by every user on this machine)"
    if ${CHECK_ONLY}; then
        info "would link it onto the desktop for convenience"
    elif [ -e "${OUTPUT_DIR}/workshop-corpus" ]; then
        info "kept            ${OUTPUT_DIR}/workshop-corpus (already present)"
    else
        # A link, not a copy. A copy would drift from what the flows actually read,
        # and would cost 13 MB again for every user who logs in.
        ln -sfn "${PREFIX}/corpus" "${OUTPUT_DIR}/workshop-corpus"
        info "linked          ${OUTPUT_DIR}/workshop-corpus -> ${PREFIX}/corpus"
    fi
fi

# ------------------------------------------------------------------ done

say "Done"
if ${CHECK_ONLY}; then
    info "That was a dry run. Run without --check to apply it."
    exit 0
fi

cat <<EOF

    Node-RED          http://127.0.0.1:1880/   (also the ViPER Workflows launcher)
    Start here        tab "0. Start here" on the canvas
    The corpus        ${PREFIX}/corpus
                      also linked at ${OUTPUT_DIR}/workshop-corpus
                      start with its README.txt
    Your output       ${OUTPUT_DIR}
    The runner        dp-run --list

  The ViPER Assistant needs an API key before it will start. It talks to OpenRouter,
  so create a key at https://openrouter.ai/keys and put it in your shell profile:

      echo 'export OPENROUTER_API_KEY=sk-or-...' >> ~/.profile

  then log out and back in. OpenRouter bills in US dollars, and a few dollars of
  credit is far more than a day's use: the default model cost about two cents for a
  full set of test questions.

  If Node-RED is not responding:

      systemctl --user status node-red
      journalctl --user -u node-red -n 50

EOF
