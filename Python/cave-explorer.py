"""
	Jean-Pierre LESUEUR (@DarkCoderSc)  
	https://www.phrozen.io/             
                                        
	Requirement:                         
	  - pip install pefile             
    - pip install colorama           
"""

import argparse
import logging
import os
import re
import struct
import sys

import pefile
from colorama import Fore, Style, init
    
init()

class ColoredBackticksFormatter(logging.Formatter):
    def format(self, record):        
        record.msg = self.highlight_backticks(record.msg)
        return super().format(record)

    def highlight_backticks(self, message):
        pattern = r'`([^`]+)`'
    
        colored_text = re.sub(pattern, lambda match: f"{Fore.GREEN}`{match.group(1)}`{Style.RESET_ALL}", message)

        return colored_text
    

def get_logger():
	logger = logging.getLogger()
	logger.setLevel(logging.DEBUG)
	formatter = ColoredBackticksFormatter("%(levelname)s - %(message)s")
	handler = logging.StreamHandler()
	handler.setFormatter(formatter)	  
	logger.addHandler(handler)
 
	return logger

    
def bytearr_to_bytestr(data):
	return ''.join(f"\\x{'{:02x}'.format(x)}" for x in data)


def bytestr_to_bytearr(data):
	return list(bytearray.fromhex(data.replace("\\x", " ")))


class CodeCave:
	def __init__(self, section, offset, size, cave_type):
		self.section = section
		self.offset = offset	
		self.size = size	
		self.type = cave_type


def get_section_name(section):
	if not section:
		return ""

	return section.Name.decode("utf-8").strip('\0').lower()


def code_cave_finder(section, cave_opcode):
	code_caves = []
    
	offset = section.VirtualAddress

	section_data = pe.get_memory_mapped_image()[offset:offset + section.SizeOfRawData]		

	cave_length = 0	

	for index, b in enumerate(section_data, start=1):			
		if (b == cave_opcode):				
			cave_length += 1	

		if ((b != cave_opcode) and (cave_length > 0)) or (index == len(section_data)):			
			if cave_length >= argv.cave_min_size:					
				code_caves.append(CodeCave(section, (index - cave_length), cave_length, cave_opcode))				
			
			cave_length = 0

	return code_caves


def hex_or_int(value):
    try:        
        return int(value)    
    except ValueError:
        try:            
            return int(value, 16)
        except ValueError:
            raise argparse.ArgumentTypeError(f"Invalid value: `{value}`. Supported values are integer or hexadecimal integer representation.")
        
        
if __name__ == "__main__":  
	logger = get_logger()		
	try:
		argument_parser = argparse.ArgumentParser(description=f"Cave Explorer (Code Cave Finder for PE executables (x86-32))")

		argument_parser.add_argument('-f', '--file', type=str, dest="file", action="store", required=True, help="x86-32 PE Input File.")
	
		argument_parser.add_argument('-c', '--cave-opcodes', type=str, dest="cave_opcodes", action="store", default="\\x00\\x90", help="OpCode considered as valid code caves (Example: NULL(0x00), NOP(0x90)).")
  
		argument_parser.add_argument('-b', '--imagebase', type=hex_or_int, dest="imagebase", action="store", default=None, help="Define a custom imagebase. Default is the one pecified imagebase by file PE Header.")

		argument_parser.add_argument('-s', '--cave-min-size', type=int, dest="cave_min_size", action="store", default=30, help="Minimum serie of opcodes to be considered as a cave (in bytes).")					
  
		argument_parser.add_argument('-v', '--verbose', type=bool, dest="verbose", action=argparse.BooleanOptionalAction, default=False, help="Increase verbosity.")		

		try:
			argv = argument_parser.parse_args()		
		except IOError as e:
			argument_parser.error()

		try:
			cave_opcode = bytestr_to_bytearr(argv.cave_opcodes)
		except:
			raise Exception("Malformed byte string. A byte string must be defined with the following format: \"\\x01\\x02\\x03...\\x0a\".")

		pe = pefile.PE(argv.file, fast_load=False)	  

		if pe.FILE_HEADER.Machine != pefile.MACHINE_TYPE["IMAGE_FILE_MACHINE_I386"]:
			raise Exception("This script is not compatible with x86-64 PE Files.")

		if argv.imagebase is None:
			imagebase = pe.OPTIONAL_HEADER.ImageBase
		else:
			imagebase = argv.imagebase
   
		logger.info("Target file: `{}`".format(argv.file))
		logger.info("Working with ImageBase->`{}`".format(format(imagebase, "08X")))
	
		logger.debug("Exploring possible code caves...")
		for section in pe.sections:
			section_name = get_section_name(section)
   
			if section.Characteristics & 0x20000000 == 0x20000000:
				logger.info("Scanning section `{}`, VA->`{}`, PointerToRawData->`{}`, Size->`{}`".format(
					section_name,
					format(section.VirtualAddress, "08X"),
					format(section.PointerToRawData, "08X"),
					format(section.SizeOfRawData, "08X"),
				))
        
				for opcode in cave_opcode:
					code_caves = code_cave_finder(section, opcode)					
     
					for index, code_cave in enumerate(code_caves):
						logger.info("Cave:{} - Offset->`{}`, RVA->`{}`, Cave Size->`{}` bytes, OpCode->`{}`".format(
							index+1,      
							format(code_cave.offset, "08X"),
							format(imagebase + code_cave.section.VirtualAddress + code_cave.offset, "08X"),
							code_cave.size,
							format(code_cave.type, "02X"),
						))
			else:
				if argv.verbose:
					logger.warning("Section `{}` is not executable, skipping...".format(section_name))    	
    
		logger.info("Done.")
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		logger.error(f"{str(e)}, line=[{exc_tb.tb_lineno}]")
