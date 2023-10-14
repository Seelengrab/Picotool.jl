# Picotool.jl

A Julia wrapper package for [picotool](https://github.com/raspberrypi/picotool), used for interacting with the Raspberry Pi Pico family of microcontrollers.

## Installation

On Linux, make sure to run `install_udev()` to install the `udev` definitions for teensy, if you haven't already set them up.

## Functions

These functions are the supported API of this package. Make sure to read their docstrings thoroughly.

 * `install_udev`
 * `help_cmd`
 * `info`
 * `version`
 * `reboot!`
 * `verify`
 * `save`
 * `load!`
