#
# Atari PIC programmer
# Copyright (C) 2016 Daniel Serpell
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>
#
###########################################################################

# Makefile: builds a bootable ATR image with all the programs.

# Output ATR filename:
ATR=picprog.atr

# Output files inside the ATR
FILES=\
    bin/readme \
    bin/picprog.com \
    bin/picread.com \
    bin/setvpp.com \
    bin/readhex.com \
    bin/startup.bat \
    bin/sample.hex \

# BW-DOS files to copy inside the ATR
DOS=\
    bin/dos/\
    bin/dos/xbw130.dos\
    bin/dos/copy.com\

# Main make rule
all: $(ATR)

# Build an ATR disk image using "mkatr".
picprog.atr: $(DOS) $(FILES)
	mkatr $@ -b $^

# Rule to remove all build files
clean:
	rm -f $(ATR)
	rm -f $(FILES)

# Assemble using MADS to a ".com" file
bin/%.com: %.asm
	mads $< -o:$@

# Compile a C file using CC65
bin/%.com: %.c
	cl65 -tatari -Osir $< -o $@ && rm $(<:.c=.o)

# Transform a text file to ATASCII (replace $0A with $B1)
bin/%: %
	tr '\n' '\233' < $< > $@

# Copy the .HEX sample to the output
bin/sample.hex: sample-16f690.hex
	cp $< $@

