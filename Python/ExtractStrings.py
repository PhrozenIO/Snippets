#!/usr/bin/env python3

# Jean-Pierre LESUEUR (@DarkCoderSc)
# https://keybase.io/phrozen

import argparse
import mmap
from itertools import chain


def extract_strings(file, min_length=4, unicode=False):
	printable_ascii = b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ "

	if unicode:
		char_size = 2
	else:
		char_size = 1

	with mmap.mmap(file.fileno(), length=0, access=mmap.ACCESS_READ) as mmap_obj:
		string = b""
		offset = 0

		for cursor in range(0, mmap_obj.size(), char_size):
			b = mmap_obj.read(char_size)
			
			if b[0] in printable_ascii:
				if char_size == 2 and b[1] != 0:
					continue

				string += b[0].to_bytes(1, byteorder='big')						
			else:					
				if len(string) >= min_length:						
					yield offset, string.decode('ascii')

				string = b""
				offset = cursor			


if __name__ == "__main__":
	parser = argparse.ArgumentParser(description=f"Binary String Extractor")

	parser.add_argument('-f', '--file', type=argparse.FileType('rb'), dest="file", required=True, help="Binary file to inspect for strings.")

	parser.add_argument('-o', '--offset', default=False, dest="show_offset", action="store_true", help="Show string location in file (string offset).")

	parser.add_argument('-l', '--min-length', default=4, required=False, dest="min_length", action="store", help="Minimum length of extracted string.")

	parser.add_argument('-m', '--extract-mode', dest="mode", default='all', choices=['all', 'ascii', 'unicode'], help="Filter string extraction by its encoding nature.")
	
	try:
		argv = parser.parse_args()		
	except IOError as e:
		parser.error()	

	ascii_strings = iter([])
	unicode_strings = iter([])

	if argv.mode == "all" or argv.mode == "ascii":
		ascii_strings  = extract_strings(argv.file, argv.min_length)

	if argv.mode == "all" or argv.mode == "unicode":
		unicode_strings = extract_strings(argv.file, argv.min_length, True)	

	for offset, string in chain(ascii_strings, unicode_strings):
		if argv.show_offset:
			print("{} : {}".format(
				offset,
				string,
			))
		else:
			print(string)
