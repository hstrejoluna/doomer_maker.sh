#!/bin/bash

process_file() {
  speed="$1"
  reverb="$2"
  low_pass_freq="$3"
  input_file="$4"
  output_folder="$5"
  filename_no_ext="$6"

  output_file="${output_folder}/${filename_no_ext}_speed${speed}_reverb${reverb}_lowpass${low_pass_freq}.mp3"
  
  ffmpeg -i "$input_file" -filter:a "asetrate=44100*$speed,aresample=44100" -vn "temp_slowed_${speed}_${reverb}_${low_pass_freq}.mp3"
  sox "temp_slowed_${speed}_${reverb}_${low_pass_freq}.mp3" "temp_low_pass_${speed}_${reverb}_${low_pass_freq}.mp3" lowpass "$low_pass_freq"
  sox "temp_low_pass_${speed}_${reverb}_${low_pass_freq}.mp3" "$output_file" reverb "$reverb" 0.5 100 100 0 0
  rm "temp_slowed_${speed}_${reverb}_${low_pass_freq}.mp3" "temp_low_pass_${speed}_${reverb}_${low_pass_freq}.mp3"
}

export -f process_file

input_file=$(zenity --file-selection --file-filter='MP3 files (mp3) | *.mp3' --title="Select an MP3 file")

if [ -z "$input_file" ]; then
  echo "No input file selected."
  exit 1
fi

output_folder=$(zenity --file-selection --directory --title="Select the output folder")
if [ -z "$output_folder" ]; then
  echo "No output folder selected."
  exit 1
fi

num_mixes=$(zenity --entry --title="Number of mixes" --text="Enter the number of doomer mixes to generate (max 27):" --entry-text="9")

if [ -z "$num_mixes" ]; then
  echo "Number of mixes not provided."
  exit 1
fi

filename=$(basename -- "$input_file")
filename_no_ext="${filename%.*}"

total_mixes=$((num_mixes < 27 ? num_mixes : 27))
current_mix=0

jobs=""
for speed in 0.8 0.9 1.0; do
  for reverb in 50 60 70; do
    for low_pass_freq in 400 600 800; do
      jobs+="$(echo "$speed $reverb $low_pass_freq")"$'\n'
      current_mix=$((current_mix + 1))
      if [ "$current_mix" -ge "$total_mixes" ]; then
        break 3
      fi
    done
  done
done

echo "$jobs" | parallel --colsep ' ' --bar process_file {1} {2} {3} "$input_file" "$output_folder" "$filename_no_ext"

zenity --info --title="Doomer Mixes Ready" --text="All doomer mixes generated in folder: $output_folder"
