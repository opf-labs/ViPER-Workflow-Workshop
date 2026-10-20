# ViPER Workflow Workshop

Node-RED preservation workflows and the ViPER Assistant, as an add-on for a stock
[ViPER](https://viper.openpreservation.org/) virtual machine.

These were demonstrated at the iPRES 2026 workshop *Exploring the Digital Preservation
Lifecycle* (Copenhagen). They ran on a Docker image built on top of ViPER, so they are
not present in the ViPER OVA or QCOW2 downloads. This repository packages them so you
can add them to your own machine.

## Licence

[Apache License 2.0](LICENSE). Use it anywhere, including commercially, with no
obligation to share changes back. It comes with **no warranty of any kind**: these
scripts modify the machine you run them on, so take a snapshot first and satisfy
yourself that they do what you want.

**Something not working?** Please
[open an issue](https://github.com/opf-labs/ViPER-Workflow-Workshop/issues/new).
Include the output of `./install.sh --check`, which reports what the installer found.

| file | what it is |
|------|------------|
| `install.sh` | the installer. This is the only file you need to download |
| `viper-workshop-extras.tar.gz` | the workshop files, fetched automatically by the installer |
| `build-tarball.sh` | maintainer tool: rebuilds the tarball from a built workshop image |

---

### A note on `build-tarball.sh`

That script is here for provenance, not for use. It rebuilds
`viper-workshop-extras.tar.gz` by extracting `/opt/workshop` from a **built** workshop
Docker image, because the flows, the notebooks, the Node-RED palette and the PRONOM
reference CSV are all generated during that image's build and do not exist as source
files anywhere.

So cloning this repository is not enough to run it: you also need the workshop image,
which is not published. If you want to rebuild the payload, ask
[Darren](https://github.com/darrendignam). **If you just want to use the workshop
material, ignore this file entirely** and follow the install instructions below.

---

## What this adds

Adds the two things from the iPRES 2026 workshop that are **not** part of ViPER itself:

- **Node-RED** with the OPF preservation palette, and the five demo workflows
- **The ViPER Assistant**, the LLM that can run the preservation tools for you

Plus the `dp-run` tool runner, the JupyterLab notebooks and the teaching corpus that the
exercises use.

## Why these are missing from the download

ViPER is the desktop and the preservation tools. The workshop ran on a **separate image
built on top of ViPER**, and the workflow and assistant layer lived there rather than in
ViPER itself. So nothing was missed on the download; those parts genuinely are not in it.

Everything here goes alongside your existing ViPER installation and changes none of the
tools already on it.

## What you need

- ViPER **2.0.0-alpha**, running in VirtualBox or any other hypervisor
- An internet connection in the VM
- About 500 MB of free disk, and 10 minutes
- The password for the `viper` account, which ships with the image
- For the Assistant only: a free **OpenRouter** account, covered at the end

One hardware note. The Assistant will not start on a CPU without **AVX** support, and it
fails with a long crash report that does not explain why. Almost every machine made
since about 2011 has it, and VirtualBox passes it through from your real CPU, so this
is unlikely to affect you. The installer checks and warns you up front if it is missing.
Node-RED and all the preservation tools are unaffected either way.

Take a VirtualBox **snapshot** before you start. Then if anything goes wrong you can roll
back in seconds rather than reinstalling the appliance.

## Installing

Inside ViPER, open **Firefox** and download the installer from the link Darren sent you.
It saves to `~/Downloads`. Then press **Ctrl+Alt+T** to open a terminal and run:

```bash
cd ~/Downloads
chmod +x install.sh
./install.sh --check      # shows what it would do, changes nothing
./install.sh              # does it
```

The script downloads everything else it needs, so this one file is all you have to fetch.

It will ask for your password, once, near the start. On a stock ViPER machine the
account is `viper` and the password is the one documented with the image.

Run it as your normal user, **not** with `sudo` in front. It asks for the password
itself when it needs to. Running the whole thing as root would put your workflows and
the assistant's settings in root's home directory instead of yours.

It takes about five to ten minutes, most of which is downloading Node.js. It is safe to
run twice: anything already installed is left alone, and your own edits to flows or
notebooks are never overwritten.

## After it finishes

**Node-RED** is at <http://127.0.0.1:1880/>, and there is a **ViPER Workflows** launcher
on the desktop. It starts automatically from now on when you log in.

Open the tab marked **0. Start here**. The five numbered tabs after it are the workflows
from the workshop:

| tab | what it shows |
|-----|---------------|
| 1. Identify a folder | identification across a folder of files, written to CSV |
| 2. Compare identifiers | fido, Siegfried and DROID on one file, and where they disagree |
| 3. Policy validation | the flagship: route each file by PUID to the right validator |
| 4. Characterisation | pulling technical metadata out of files |
| 5. OCR to PDF/A | making a searchable archival PDF, then checking the claim |

**The teaching corpus** is on your desktop at `workshop-corpus`. Start with its
`README.txt`. The flows are already pointed at it, so they run as soon as you open them.

**The notebooks** are the same exercises written as Python, via the **ViPER Notebooks**
launcher. JupyterLab is not part of ViPER, so the installer adds it in its own
virtualenv at `/opt/jupyter`, leaving ViPER's own Python untouched.

**The command line** works too:

```bash
dp-run --list                                        # every tool and its options
dp-run fido ~/Desktop/workshop-corpus/01-identification/mystery-file-1.dat
dp-signatures                                        # which PRONOM release each tool reads
```

## Turning on the Assistant

The Assistant talks to [OpenRouter](https://openrouter.ai/), which gives you a single key
for many different models. It needs a key before it will start.

1. Make an account at <https://openrouter.ai/> and create a key at
   <https://openrouter.ai/keys>
2. Add a small amount of credit. This is genuinely cheap: the default model cost about
   **two cents** for a full set of test questions during development. OpenRouter bills
   in US dollars, and a few dollars will outlast your curiosity.
3. Put the key in your shell profile:

   ```bash
   echo 'export OPENROUTER_API_KEY=sk-or-...' >> ~/.profile
   ```

4. Log out and back in, then launch **ViPER Assistant** from the desktop.

Ask it things like:

- *What is this file, and how confident are you?* with a path from the corpus
- *Run fido and DROID on this file and explain any disagreement*
- *Build me a Node-RED flow that validates every PDF in a folder*

It has a written brief covering the tools, PRONOM, and how to behave: it is told to run
the tools rather than guess, and to say when it does not know. You can read that brief at
`/opt/workshop/agent/AGENTS.md`, and add your own instructions in `~/AGENTS.md`.

## Differences from the workshop machines

- **No shared upload folder.** That was a service on the workshop server.
- **No JHOVE test corpora.** The workshop machines mounted a 320-file set. The flows here
  point at the teaching corpus instead. If you want the full set, the JHOVE project
  publishes it and you can point any `files` node at wherever you put it.
- **Node-RED runs as a systemd user service**, not under s6 as it did in the container.
  If it is ever not responding:

  ```bash
  systemctl --user status node-red
  journalctl --user -u node-red -n 50
  ```

- **Siegfried** was an addition on the workshop image. The installer adds it, so flow 2
  can compare it against fido and DROID.
- **The Arlington PDF Model Checker** has a desktop icon in ViPER but no command-line
  version, so the one step of flow 3 that uses it reports the tool as unavailable.
  Everything else is unaffected.
- **fido's signatures are older here, and this one is worth fixing.** See the next
  section.

## Updating fido's PRONOM signatures

ViPER ships fido with **PRONOM v109**. The workshop machines were on **v125**, sixteen
releases newer. Most everyday formats identify identically either way, but recent ones
are simply absent from v109, so fido reports them as unidentified. JPEG 2000 part 15
(`fmt/1964`) is the one you will hit first, because the teaching corpus includes it.

Check what you have:

```bash
dp-signatures
```

The obvious fix does not work:

```bash
fido -sigs update
Your signature files are up to date, current version is v109
```

That is not fido being wrong. Its default update site stopped publishing new releases,
so it correctly reports that it has the newest version *that site offers*. The OPF runs
a replacement service, and pointing fido at it makes the update work:

```bash
# Ask fido which Python it runs under, then ask that Python where fido lives.
# Going via the shebang matters: fido is not always installed into the system
# Python, so `python3 -c "import fido"` can fail even though fido works fine.
FIDO_PY="$(head -1 "$(command -v fido)" | sed 's|^#!||' | awk '{print $1}')"
CONF="$("$FIDO_PY" -c 'import os, fido; print(os.path.join(os.path.dirname(fido.__file__), "conf"))')"

# point it at the OPF signature service instead of the stale default
sudo sed -i 's|<updateSite>.*</updateSite>|<updateSite>https://fidosigs.opf-labs.org</updateSite>|' "$CONF/versions.xml"

# now the update finds something
sudo fido -sigs update
fido -v
```

Run on a stock ViPER that gives:

```
before:  FIDO v1.6.1 (formats-v109.xml, container-signature-20200121.xml, ...)
         Updated signatures v125 are available, current version is v109
         Updating signature file to 125.
after:   FIDO v1.6.1 (formats-v125.xml, container-signature-20200121.xml, ...)
```

Note the container signature does not move. fido freezes that deliberately, so it can
be current on the format list and years behind on container formats at the same time.
`dp-signatures` reports both, separately, for exactly that reason.

`fido -v` should then name `formats-v125.xml` or newer. Run `dp-signatures` again to
confirm, and to see how fido now compares with Siegfried and DROID.

This only affects fido. Siegfried installs with a current signature already, and DROID
updates itself through its own GUI, which is why the three disagree out of the box.
**That disagreement is itself one of the workshop's exercises**: when tools differ, check
whether they are reading the same PRONOM release before concluding one of them is wrong.

## If something goes wrong

Run `./install.sh --check` and read what it reports. It lists which preservation tools it
found, which Node.js it will use, and every change it intends to make.

The most common problem is no internet in the VM, which shows up as the Node.js step
failing. Everything else is local.

If you get stuck, reply to Darren with the output of:

```bash
./install.sh --check
node -v; node-red --version; dp-run --list | head
```

## What this does not change

Nothing already in ViPER. All the preservation tools, DROID, JHOVE, veraPDF, jpylyzer,
MediaInfo, MediaConch, ExifTool, OCRmyPDF, the ODF validator, stay exactly as they are,
at the same versions. This only adds the workflow and assistant layer on top, in
`/opt/workshop`, plus launchers and the corpus in your home directory.

To remove it all again:

```bash
systemctl --user disable --now node-red
sudo rm -rf /opt/workshop /usr/local/bin/dp-* /usr/local/bin/viper-{workflows,notebooks,assistant}
rm -rf ~/.node-red ~/Desktop/workshop-corpus ~/.config/systemd/user/node-red.service
```
