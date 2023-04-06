# Doomer_maker.sh

doomer_maker.sh is a Bash script that creates multiple "doomer mix" versions of a given MP3 file using various settings, and lets you choose the best one. It utilizes FFmpeg, Sox, and Zenity to generate the mixes and provide a user-friendly interface.

## Features

- File chooser dialog for selecting the input MP3 file
- Folder chooser dialog for selecting the output folder
- Entry dialog for specifying the number of mixes to generate (up to 27)
- Parallelized processing for faster mix generation
- Progress bar during mix generation

## Requirements

- FFmpeg
- Sox
- Zenity
- GNU Parallel

## Installation

1. Clone the repository:

```bash
git clone https://github.com/yourusername/doomer-mix-generator.git

2. Change the permissions to make the script executable:

Usage
Run the script:

./doomer-mix-generator/doomer_mix.sh

The script will open file chooser dialogs for selecting the input MP3 file and output folder, as well as an entry dialog for specifying the number of mixes to generate. After the process is complete, a message will inform you that the mixes are ready.

## License

This project is licensed under the GNU General Public License v2.0 - see the [LICENSE](LICENSE) file for details.

