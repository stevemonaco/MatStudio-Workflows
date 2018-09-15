# MatStudio-Workflows
A collection of perl scripts that automate computational chemistry calculations within Materials Studio via the MaterialScript API.

## High-throughput Workflow
Intended for repetitive workflows with user-defined calculation settings within Materials Studio. Outputs band structure and polarizability parameters useful for semiconductor candidate screening.

  ### Documentation
  Extensive installation documentation and usage instructions for High-throughput Workflow are included as a Word document.

## Pressure Series Workflow
This script continuously pressurizes crystal systems in a stepwise fashion without the interruptions associated with manual calculations. Calculation settings hardcoded to Schatschneider group settings, but can be modified in the source code.

## Molecule-In-A-Box
Script that takes a crystal system as input and outputs a gas-phase MIB structure with specified nearest-neighbor distance. Only valid for single-component crystalline systems.

## Running
These scripts must be added to the Material Studio "User Menu" for scripts and configured. See the Materials Studio documentation for details. Molecule-In-A-Box may run on the local client.

## Background
These scripts were developed for Bohdan Schatschneider's computational chemistry research group. They are being archived here on Github so that the group and interested individuals can access them. This repository aims to improve upon the lack of public availability of Materials Studio scripts.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
