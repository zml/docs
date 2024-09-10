import sys
exit = sys.exit


def main(args):
    if len(args) != 3:
        print("Usage: python split.py input.smd output.smd output.md")
        exit(1)

    smd_in, smd_out, md_out = args

    with open(smd_in, 'rt') as f:
        # f_smd_out = open(smd_out, 'wt')
        # f_md_out = open(md_out, 'wt')

        lines_smd = []
        lines_md = []
        seen_first_sep = False
        seen_second_sep = False
        for line in f.readlines():
            if seen_second_sep:
                lines_md.append(line)
            else:
                lines_smd.append(line)
                if line.strip() == '---':
                    if seen_first_sep:
                        seen_second_sep = True
                    else:
                        seen_first_sep = True
    if not lines_smd:
        print("ERROR: did not produce any YAML lines")
        exit(1)
    with open(smd_out, 'wt') as f:
        for line in lines_smd:
            f.write(f'{line}')
    with open(md_out, 'wt') as f:
        for line in lines_md:
            f.write(f'{line}')


if __name__ == '__main__':
    main(sys.argv[1:])
