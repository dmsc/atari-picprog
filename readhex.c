/*
 *  Atari PIC programmer
 *  Copyright (C) 2016 Daniel Serpell
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program.  If not, see <http://www.gnu.org/licenses/>
 */

/*
 * readhex.c: parse an .hex file with a PIC firmware and generates
 *            a program capable of programming the PIC.
 *
 * Compile with ' cl65 -tatari -Osir readhex.c -o readhex.com
 *
 * NOTE: this program is "simplified" to be able to compile with CC65.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

// List of PICs
struct pics_data
{
    const char *name;
    unsigned device_id;
    unsigned max_addr;
    unsigned id_addr;
    unsigned last_addr;
} pic_list[] =
{
    { "1: PIC16F690",  0x1400, 0x1000, 0x2000, 0x2008 },
    { "2: PIC12F675",  0x0FC0, 0x0400, 0x2000, 0x2008 },
    { "3: PIC16F1847", 0x1480, 0x2000, 0x8000, 0x8009 },
    { "4: PIC16F1936", 0x2360, 0x2000, 0x8000, 0x8009 }
};
#define pic_list_size ((uint8_t)(sizeof(pic_list)/sizeof(pic_list[0])))

struct pics_data pic;

// Our line buffer
static char line[256];
static uint8_t line_len;

// Parsed line buffer
static uint8_t buffer[128];
static uint8_t buf_len;

// Address currently writing
static int current_addr;

// High byte of current address
static int high_addr;

// Input file
static FILE *hex_file;

// Output script bufffer
static uint8_t script_buffer[30000];
static uint8_t *output_ptr;

/* Writes one character to the script buffer */
#define output_write(a) *(output_ptr++) = (a)

/* Returns the "hex" value at position */
static uint8_t parse_line(void)
{
    static uint8_t i, chk;
    static char c;

    buf_len = 0;
    if( *line != ':' )
    {
        puts("mising ':' in record");
        return 1;
    }

    chk = 0;
    for(i=1; i<line_len; i++)
    {
        static uint8_t b;
        c = line[i];
        if( c >= 'a' && c <= 'f' )
            b = c - ('a' - 10);
        else if( c >= 'A' && c <= 'F' )
            b = c - ('A' - 10);
        else if( c >= '0' && c <= '9' )
            b = c - '0';
        else
        {
            putchar(c);
            puts(": invalid hex character");
            return 1;
        }
        b <<= 4;
        i++;
        c = line[i];
        if( c >= 'a' && c <= 'f' )
            b |= c - ('a' - 10);
        else if( c >= 'A' && c <= 'F' )
            b |= c - ('A' - 10);
        else if( c >= '0' && c <= '9' )
            b |= c - '0';
        else
        {
            putchar(c);
            puts(": invalid hex character");
            return 1;
        }

        chk = chk + b;
        buffer[buf_len] = b;
        buf_len ++;
    }
    if( chk != 0 )
    {
        puts("record bad checksum");
        return 1;
    }
    if( buf_len < 5 )
    {
        puts("record too short");
        return 1;
    }
    if( buffer[0] + 5 != buf_len )
    {
        puts("bad record length");
        return 1;
    }
    buf_len --;
    return 0;
}

/* Parse and output a "data line" */
static uint8_t output_data()
{
    register uint8_t ln;
    register uint8_t *ptr;
    static int addr;
    addr = (buffer[1]<<8) + buffer[2];
    if( addr & 1 )
    {
        puts("new address can not be odd");
        return 1;
    }
    addr >>= 1;
    addr |= high_addr;

    if( addr >= pic.last_addr )
    {
        puts("address out of range");
        return 1;
    }
    if( addr >= pic.id_addr )
    {
        // Go to ID programming
        if( current_addr < pic.id_addr )
        {
            // Script write: 00 00 = go to config area
            output_write(0);
            output_write(0);
            current_addr = pic.id_addr;
        }
    }
    else if( addr >= pic.max_addr )
    {
        puts("address out of program memory");
        return 1;
    }

    if( addr < current_addr )
    {
        puts("new address is lower than current");
        return 1;
    }
    while( addr > current_addr )
    {
        static unsigned dif;
        dif = addr - current_addr;
        if( dif > 255 )
            dif = 255;
        // Script write: SKIP bytes
        output_write(0);
        output_write(dif&0xFF);
        current_addr += dif;
    }

    ln = buffer[0] >> 1;
    if( !ln )
    {
        puts("invalid data length");
        return 1;
    }

    // Write words: LEN
    output_write(ln);
    ptr = buffer + 4;
    while( ln > 0 )
    {
        // Word to program
        output_write(ptr[0]);
        output_write(ptr[1]);
        ln --;
        ptr += 2;
        current_addr ++;
    }
    return 0;
}

/* Parse a "linear address" line */
static uint8_t linear_addr()
{
    if( buffer[0] != 2 || buffer[1] != 0 || buffer[2] != 0 )
    {
        puts("invalid linear address");
        return 1;
    }
    if( buffer[4] != 0 || buffer[5] > 1 )
    {
        puts("addresses > $1FFFF not supported");
        return 1;
    }
    high_addr = buffer[5] ? 0x8000 : 0x0000;
    return 0;
}

/* Parse one line of input */
static uint8_t interpret_line()
{
    register uint8_t record;

    record = buffer[3];
    switch( record )
    {
        case 0: // Data to program
            return output_data();
        case 1: // End of file, ignore
            return 0;
        case 4:
            return linear_addr();
        default:
            puts("unknown record type");
            return 1;
    }
    return 1;
}

//--------------------
static char *hex_name;

/* Parse hex file and output a new programing file. */
static uint8_t parse_hex(void)
{
    static int line_num;
    hex_file = fopen(hex_name, "r");
    if( !hex_file )
    {
        puts("error opening input file");
        return 1;
    }
    // init:
    current_addr = 0;
    high_addr = 0;
    line_num = 0;

    // Script start:
    output_ptr = script_buffer;
    // writes device id
    output_write(pic.device_id & 0xFF);
    output_write(pic.device_id >> 8);
    // writes script end
    output_write(0);
    output_write(0);
    // process input file
    while( !feof(hex_file) )
    {
        // Parse line by line
        line_len = 0;
        line_num ++;
        putchar('.');
        while(1)
        {
            register int c = fgetc(hex_file);
            if( c == EOF )
                break;
            if( c == 13 )
                c = fgetc(hex_file);
            if( c == 10 )
                break;
            line[line_len] = c;
            line_len ++;
        }

        if( line_len )
        {
            if( parse_line() || interpret_line() )
            {
           //     printf("- error at line %d, ending\n", line_num);
                fclose(hex_file);
                return 1;
            }
        }
    }
    putchar('\n');
    fclose(hex_file);

    return 0;
}

//--------------------
static char *out_name;

static uint8_t write_output(void)
{
    static char *orig_name = "PICPROG.COM";
    static FILE *out_prog;
    static FILE *com_file;
    static int c;
    register unsigned pos;

    // Now, writes the full program
    puts("Writing the output programming COM.\n");
    out_prog = fopen(out_name, "w");
    if( !out_prog )
    {
        puts("error: open output file");
        return 1;
    }

    // - start: the current pic-prog:
    com_file = fopen(orig_name, "rb");
    if( !com_file )
    {
        puts("error: open input 'PICPROG.COM'");
        fclose(out_prog);
        return 1;
    }
    while(1)
    {
        c = fgetc(com_file);
        if( c == EOF )
            break;
        fputc(c, out_prog);
    }
    fclose(com_file);

    // Patched the script_end:
    {
        pos = 0x2C00 + output_ptr - script_buffer;
        script_buffer[2] = pos & 0xFF;
        script_buffer[3] = pos >> 8;
    }

    // - new segment header: start = $2C00
    fputc( 0x00, out_prog);
    fputc( 0x2C, out_prog);
    // - ending
    pos --;
    fputc( pos & 0xFF, out_prog);
    fputc( pos >> 8, out_prog);

    // Copy all bytes
    {
        register uint8_t *pos = script_buffer;
        while( pos != output_ptr )
            fputc( *(pos++), out_prog);
    }
    fclose(out_prog);
    return 0;
}

/* Shows a list of supported PICs and lets the user select one */
void select_pic()
{
    static char buf[8];
    static uint8_t i;
    do
    {
        puts("Select the PIC to program:");
        for(i=0; i<pic_list_size; i++)
            puts(pic_list[i].name);
        puts("Number?");
        gets(buf);
        i = buf[0] - '1';
    }
    while( i >= pic_list_size );
    memcpy(&pic, &pic_list[i], sizeof(pic_list[0]));
}

int main(int argc, char **argv)
{
    static char outbuf[64];
    if( argc < 2 )
    {
        static char buf[64];
        puts("Input HEX file name?");
        gets(buf);
        hex_name = buf;
    }
    else if( argc < 3 )
    {
        hex_name = argv[1];
    }
    else
    {
        hex_name = argv[1];
        out_name = argv[2];
    }

    if( !out_name )
    {
        static int p;
        p = strrchr(hex_name, '.') - hex_name;
        if( p > 255 )
        {
            strcpy(outbuf,hex_name);
            strcat(outbuf,".COM");
        }
        else
        {
            memcpy(outbuf, hex_name, p);
            memcpy(outbuf+p, ".COM", 4);
        }
        out_name = outbuf;
    }

    select_pic();

    if( !parse_hex() && !write_output() )
        puts("\nOk.");

    puts("press RETURN to end");
    getchar();
    return 0;
}
