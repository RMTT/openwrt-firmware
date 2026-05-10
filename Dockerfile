FROM ubuntu:24.04

COPY ./setup.sh /setup.sh

RUN ./setup.sh
