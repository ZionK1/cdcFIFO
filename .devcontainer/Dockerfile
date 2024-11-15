FROM ghcr.io/ucsc-cse-x25/sp24-dockerimages:base

ENV LANG C.UTF-8
ARG INSTALL_ZSH="true"

RUN apt-get install npm
RUN cd /opt && git clone https://github.com/nturley/netlistsvg
RUN cd /opt/netlistsvg && npm install --legacy-peer-deps && npm install . -g

RUN pip install pillow

RUN apt-get -y install sudo
RUN useradd -ms /bin/bash cse-x25-student -G sudo -p "$(openssl passwd -1 ilikehdl)"
USER cse-x25-student

ENV PATH="/usr/local/bin/tabby/bin:$PATH"
ENV YOSYSHQ_LICENSE="/usr/local/bin/tabby/license/yosyshq.lic"
