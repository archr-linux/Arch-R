FROM archlinux:latest

SHELL ["/usr/bin/bash", "-c"]

# Update system and install base packages
# Fix: archlinux:latest has corrupt pacman local db (missing desc files in overlay)
# Step 1: upgrade base system (creates new layer, fixes stale db entries)
RUN pacman-db-upgrade 2>/dev/null; \
    for pkg in /var/lib/pacman/local/*/; do \
      [ ! -f "${pkg}desc" ] && rm -rf "$pkg" 2>/dev/null; \
    done; true
RUN pacman -Syu --noconfirm
# Step 2: clean stale entries from previous layer, then install build deps
RUN for pkg in /var/lib/pacman/local/*/; do \
      [ ! -f "${pkg}desc" ] && rm -rf "$pkg" 2>/dev/null; \
    done; true
RUN pacman -S --noconfirm --needed \
    base-devel bc jdk-openjdk file gawk gettext git go gperf \
    perl-json perl-xml-parser ncurses lzop make patchutils \
    python python-setuptools parted unzip wget curl \
    xorg-mkfontscale libxslt zip vim zstd rdfind automake \
    xmlstarlet rsync which sudo rpcsvc-proto perl-parse-yapp xorg-bdftopcf \
    dtc python-pip
# Python fdt package for MIPI panel overlay generation
RUN pip3 install --break-system-packages fdt

# Note: GCC downgrade removed - build system compiles its own cross-toolchain (GCC 15.1).
# Host GCC is only used for host tools. Fixes from projects/ArchR/packages/ handle
# any GCC 15 incompatibilities in individual packages (spirv-tools, llvm, etc.)

# Create build user
RUN useradd -m -s /bin/bash docker && \
    echo 'docker ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set locale
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Ensure Perl tools (pod2man, yapp, etc.) are in standard PATH
RUN for f in /usr/bin/core_perl/*; do [ -f "$f" ] && ln -sf "$f" /usr/bin/ 2>/dev/null; done; \
    for f in /usr/bin/vendor_perl/*; do [ -f "$f" ] && ln -sf "$f" /usr/bin/ 2>/dev/null; done; \
    true

### Cross compiling on ARM
RUN if [ "$(uname -m)" = "aarch64" ]; then pacman -S --noconfirm qemu-user-static; fi
RUN if [ ! -d /lib64 ]; then ln -sf /usr/x86_64-archr-linux-gnu/lib64 /lib64 2>/dev/null || true; fi
RUN if [ ! -d /lib/x86_64-archr-linux-gnu ]; then ln -sf /usr/x86_64-archr-linux-gnu/lib /lib/x86_64-archr-linux-gnu 2>/dev/null || true; fi

RUN mkdir -p /work && chown docker /work

# Git safe.directory for any user (env-file may override HOME)
RUN git config --system --add safe.directory '*'

WORKDIR /work
USER docker
