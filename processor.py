import sys
import os
import re
from dataclasses import dataclass
from typing import Union, Tuple
from pathlib import Path


# action dataclasses for logging
@dataclass
class CreateDirAction:
    directory: str

@dataclass
class TranslateLinkAction:
    source_file: str      # the .smd or .md source file
    original: str         # the original link
    destination: str      # the rewritten link

@dataclass
class MergeIntoSmdAction:
    smd_dest: str         # the resulting combined .smd file
    smd_source: str       # the .smd (yaml header) file
    md_source: str        # the .md (content) file

@dataclass
class SplitSmdAction:
    source_file: str      # the .smd source file
    smd_dest: str         # the .smd (yaml header) file
    md_dest: str          # the .md (content) file

@dataclass
class ProcessingFileAction:
    source_file: str      # the file being processed

@dataclass
class IgnoreFileAction:
    source_file: str      # the file being processed
    reason: str

@dataclass 
class TranslateImageAction:
    source_file: str
    original: str
    destination: str


Action = Union[CreateDirAction, TranslateLinkAction, MergeIntoSmdAction,
               SplitSmdAction, ProcessingFileAction, IgnoreFileAction, 
               TranslateImageAction]


# helper functions
def find_files_with_extension(directory: str, extension: str) -> list[str]:
    """
    Returns a list of files with the given extension within the specified 
    directory and its subdirectories.

    :param directory: The path to the directory to search in.
    :param extension: The file extension to look for (e.g., '.smd').
    :return: A list of file paths with the specified extension.
    """
    assert extension.startswith('.')
    matching_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(extension):
                matching_files.append(os.path.join(root, file))
    return matching_files

def extension_of(file: str) -> str:
    _, extension = os.path.splitext(file)
    return extension

def has_extension(file: str, ext: str) -> bool:
    return extension_of(file) == ext

def change_extension(file: str, ext: str) -> bool:
    assert ext.startswith('.')
    base, _ = os.path.splitext(file)
    return f'{base}{ext}'

def rename_basename(path: str, new_name: str) -> str:
    components = path.split('/')[:-1]
    components.append(new_name)
    return '/'.join(components)

def remove_enclosing_slashes(path: str) -> str:
    if path.startswith('/'):
       path = path[1:]
    if path.endswith('/'):
        path = path[:-1]
    return path

def get_matching_path(file: str, strip_path: str, prepend_path: str) -> str:
    # we're doing this entirely text-based for now
    strip_path = remove_enclosing_slashes(strip_path)
    file = remove_enclosing_slashes(file)
    prepend_path = remove_enclosing_slashes(prepend_path)
    if not file.startswith(strip_path):
        raise ValueError(f'file `{file}` does not seem to be in {strip_path}')
    sub_path = remove_enclosing_slashes(file[len(strip_path):])
    return f'{prepend_path}/{sub_path}'

def get_dir_of(path: str) -> str:
    path, _ = os.path.split(path)
    return path

def resolve_link(md_root: str, md_file: str, relative_link: str) -> str:
    """
    Resolve the relative link within the context of the md_root.

    :param md_root: The root directory for markdown files.
    :param md_file: The path to the markdown file where the link is found.
    :param relative_link: The relative link target within the markdown file.
    :return: The resolved path of the link within md_root.
    """
    # Convert the paths to Path objects
    md_root_path = Path(md_root)
    md_file_path = Path(md_file)
    # Combine md_file_path with the relative link to get the full target path
    link_target_path = (md_file_path.parent / relative_link).resolve()
    # Calculate the relative path of the link target within md_root
    resolved_path = link_target_path.relative_to(md_root_path.resolve())
    return str(resolved_path)

def create_relative_link(md_root: str, md_file: str, relative_link: str) -> str:
    """
    Creates a relative link for a markdown file given the root directory, the 
    file location, and the link starting with a slash.
    
    Args:
        md_root (str): The root directory of all markdown files.
        md_file (str): The path to the markdown file containing the link.
        relative_link (str): The link that starts with a slash (from root).
    
    Returns:
        str: The resolved relative link.
    """
    # Ensure the relative_link starts with a slash and remove it for path operations
    if not relative_link.startswith('/'):
        raise ValueError("The relative_link should start with a slash ('/').")
    # Remove the leading slash from the relative link to make it a relative path
    link_path = relative_link.lstrip('/')
    # Get the directory of the markdown file
    md_file_dir = os.path.dirname(md_file)
    # Compute the relative path from the markdown file to the root
    relative_path_to_root = os.path.relpath(md_root, md_file_dir)
    # Join the computed path with the link path to form the resolved link
    resolved_link = os.path.join(relative_path_to_root, link_path)
    return resolved_link


class Github2Zine:
    def __init__(self, gh_path:str, zine_path:str, workspace_path:str, dry_run: bool):
        self.gh_path = gh_path
        self.zine_path = zine_path
        self.workspace = workspace_path
        self.dry_run = dry_run
        self.actions: list[Action] = []

    def process(self):
        """
        Process the entire GH docs collection
        Calls process_file on all files.
        Collects actions in `actions`.
        """
        # first, scan all files we need to process
        # when we actually process, we need to make sure that a corresponding zine
        # file exists
        md_sources = find_files_with_extension(self.gh_path, '.md')
        for source_md in md_sources:
            self.actions.append(ProcessingFileAction(source_file=source_md))
            smd_yaml_src = get_matching_path(file=source_md,
                                             strip_path=self.gh_path,
                                             prepend_path=self.zine_path)
            smd_yaml_src = change_extension(smd_yaml_src, '.smd')
            if os.path.basename(smd_yaml_src) == 'README.smd':
                smd_yaml_src = rename_basename(smd_yaml_src, 'index.smd')
            if not os.path.exists(smd_yaml_src):
                self.actions.append(IgnoreFileAction(source_file=source_md,
                    reason=f'Matching .smd file {smd_yaml_src} does not exist'))
                continue
            self.process_file(source_md, smd_yaml_src)


    def process_file(self, md_path: str, smd_src_path: str):
        """
        Processes a single file:
            - rewrites links
            - 'renames' to appropriate .smd
            - returns both rewritten content and renamed file

        If self.dry_run is False, the content is appended to the `smd` file in 
        the Zine docs collection. 
        """
        # read content
        with open(md_path, 'rt') as f:
            content = f.read()

        # rewrite content
        new_content = self.rewrite_content(content, md_path)

        # read the source smd file for YAML
        with open(smd_src_path, 'rt') as f:
            yaml = f.read()

        # append the new_content to the smd content
        new_content = f'{yaml}\n{new_content}'

        # smd dest path = smd_src_path in the WORKDIR
        smd_dest_path = get_matching_path(
                file=smd_src_path,
                strip_path=self.zine_path,
                prepend_path=os.path.join(self.workspace, 'content'))

        # create the workdir subdirs if necessary
        smd_dirs = get_dir_of(smd_dest_path)
        if not os.path.exists(smd_dirs):
            self.actions.append(CreateDirAction(directory=smd_dirs))
            if not self.dry_run:
                os.makedirs(smd_dirs, exist_ok=False)
        # create the workdir smd file
        self.actions.append(MergeIntoSmdAction(
            smd_dest=smd_dest_path, smd_source=smd_src_path, md_source=md_path))
        if not self.dry_run:
            with open(smd_dest_path, 'wt') as f:
                f.write(new_content)
        return


    def rewrite_link(self, relative_path: str, link_text: str, target: str):
        original = target
        if '#' in target:
            target, anchor = target.split('#', 1)
            anchor = f'#{anchor}'
        else:
            anchor = ''

        if target and not target.endswith('.md'):
            raise ValueError(f'Link target `{target}` in {relative_path} does not point to a .md file!')

        if target:
            resolved = resolve_link(self.gh_path, relative_path, target)
            target_file = os.path.basename(resolved)
            target_dir = os.path.dirname(resolved)
            if target_file == 'README.md':
                target_file = '' # -> index.smd
            else:
                # strip extension
                target_file, _ = os.path.splitext(target_file)
            if target_dir:
                target_dir = f'/{target_dir}'
            new_target = f'{target_dir}/{target_file}{anchor}'
        else:
            new_target = anchor

        link_url = f'[{link_text}]({new_target})'
        self.actions.append(TranslateLinkAction(source_file=relative_path,
                                                original=original,
                                                destination=new_target))
        return link_url

    # TODO: this is temp until loris fixes zine
    def rewrite_image_link(self, relative_path, img_text, img_target):
        new_target = f"[{img_text}]($image.url('{img_target}'))"
        self.actions.append(TranslateImageAction(source_file=relative_path,
                                                original=img_target,
                                                destination=new_target))
        return new_target

    def rewrite_content(self, markdown_content:str, relative_path:str) -> str:
        """
        - rewrites markdown links
        - but ignores image links ![imgtext](imglink)
        - also handles newlines in links
        """
        link_pattern = re.compile(r'(?<!\!)\[([^\]]*?)\]\(([^)]+)\)', re.DOTALL)
        image_link_pattern = re.compile(r'!\[([^\]]*?)\]\(([^)]+)\)', re.DOTALL)

        def handle_link(match: re.Match[str]) -> str:
            # Replace newlines in link text with spaces
            link_text = match.group(1).replace('\n', ' ')
            # Get the link target and strip any extra whitespace
            target = match.group(2).strip()  
            if target.startswith('http'):
                # Return the original link if it's a web URL
                return match.group(0)  
            else:
                # Rewrite the link if it's not an HTTP URL
                rewritten_link = self.rewrite_link(relative_path,
                                                   link_text, target)
                return rewritten_link

        def handle_image_link(match: re.Match[str]) -> str:
            # Replace newlines in image text with spaces
            img_text = match.group(1).replace('\n', ' ')
            # Get the image target and strip any extra whitespace
            img_target = match.group(2).strip()
            rewritten_image_link = self.rewrite_image_link(relative_path,
                                                           img_text,
                                                           img_target)
            return rewritten_image_link
        
        # Replace all links in the markdown content using the handle_link function
        rewritten_content = link_pattern.sub(handle_link, markdown_content)

        # now the images
        rewritten_content = image_link_pattern.sub(handle_image_link,
                                                   rewritten_content)
        return rewritten_content


class Zine2Github:
    def __init__(self, gh_path:str, zine_path:str, workspace_path:str, dry_run: bool):
        self.gh_path = gh_path
        self.zine_path = zine_path
        self.workspace = workspace_path
        self.dry_run = dry_run
        self.actions: list[Action] = []

        self.link_pattern = re.compile(r'(?<!\!)\[([^\]]*?)\]\(([^()]*(\([^()]*\)[^()]*)*)\)', re.DOTALL)
        self.image_link_pattern = re.compile(r'!\[([^\]]*?)\]\(([^)]+)\)', re.DOTALL)
        self.image_link_pattern = re.compile(r'(?<=\!)\[([^\]]*?)\]\(([^()]+(?:\([^()]*\)[^()]*)*)\)', re.DOTALL)

    def process(self):
        """
        Process the entire zine docs collection
        Calls process_file on all files.
        Collects actions in `actions`.
        """
        # first, scan all files we need to process
        # when we actually process, we need to make sure that a corresponding zine
        # file exists
        smd_sources = find_files_with_extension(self.workspace, '.smd')
        for source_smd in smd_sources:
            if '.zig-cache' in source_smd:
                continue
            self.actions.append(ProcessingFileAction(source_file=source_smd))
            dest_smd_yaml = get_matching_path(
                    file=source_smd,
                    strip_path=os.path.join(self.workspace, 'content'),
                    prepend_path=self.zine_path)
            dest_md = get_matching_path(
                    file=source_smd,
                    strip_path=os.path.join(self.workspace, 'content'),
                    prepend_path=self.gh_path)
            dest_md = change_extension(dest_md, '.md')

            if os.path.basename(dest_smd_yaml) == 'index.smd':
                dest_md = rename_basename(dest_md, 'README.md')
            if not os.path.exists(dest_md):
                # TODO: we should create it! orelse we will never be able
                #       to add new .smd files w/o touching the zml/docs first
                #        we could ignore README.md but they don't harm
                #        update: we only create it further down, if there's actual
                #        content!
                # self.actions.append(IgnoreFileAction(source_file=source_smd,
                #     reason=f'Matching `{dest_md}` for {source_smd} does not exist'))
                # continue
                pass
            self.process_file(source_smd, dest_smd_yaml, dest_md)


    def process_file(self, source_smd: str, dest_smd_yaml: str, dest_md: str):
        """
        Processes a single file:
            - rewrites links
            - rewrites images

        If self.dry_run is False, the input SMD file will be split into its
        SMD (YAML) part and MD (content) part. The md part will be written to 
        the GH repo. The SMD part will be written to the SMD file in the 
        docs repo.
        """
        # read content
        with open(source_smd, 'rt') as f:
            content = f.read()
        # rewrite content
        new_content = self.rewrite_content(content, source_smd)
        yaml, new_content = self.split_yaml_and_content(new_content, source_smd)

        # create the smd subdirs if necessary
        smd_dirs = get_dir_of(dest_smd_yaml)
        if not os.path.exists(smd_dirs):
            self.actions.append(CreateDirAction(directory=smd_dirs))
            if not self.dry_run:
                os.makedirs(smd_dirs, exist_ok=True)

        # create the md subdirs if necessary
        if new_content:
            if not os.path.exists(dest_md):
                md_dirs = get_dir_of(dest_md)
                if not os.path.exists(md_dirs):
                    self.actions.append(CreateDirAction(directory=md_dirs))
                    if not self.dry_run:
                        os.makedirs(md_dirs, exist_ok=True)

        # create the workdir smd file
        self.actions.append(SplitSmdAction(source_file=source_smd,
                                           smd_dest=dest_smd_yaml,
                                           md_dest=dest_md))
        if not self.dry_run:
            with open(dest_smd_yaml, 'wt') as f:
                f.write(yaml)
            if new_content.strip():
                with open(dest_md, 'wt') as f:
                    f.write(new_content)
        return

    def rewrite_link(self, relative_path: str, link_text: str, target: str):
        original = target
        if '#' in target:
            target, anchor = target.split('#', 1)
            anchor = f'#{anchor}'
        else:
            anchor = ''

        if original.startswith('#'):
            # anchor-only
            return f'[{link_text}]({original})'

        if not target.startswith('/') and not target.startswith('$image'):
            raise ValueError(f"ERROR: In {relative_path} link target {target} must be absolute path or $image.url")

        # deal with $image.url('')
        if target.startswith('$image'):
            pattern = re.compile(r"\$image\.url\('([^']+)'\)")
            match = pattern.search(target)
            if not match:
                raise ValueError(f"ERROR: In {relative_path}: expected $image.url('...') in {target}")
            target_url = match.group(1)
            link_url = f'![{link_text}]({target_url})'
            self.actions.append(TranslateImageAction(source_file=relative_path,
                                                     original=target,
                                                     destination=target_url))
            return link_url

        if target:
            resolved = create_relative_link(
                    md_root=os.path.join(self.workspace, 'content'),
                    md_file=relative_path,
                    relative_link=target)
            target_file = os.path.basename(resolved)
            target_dir = os.path.dirname(resolved)

            # find the target file in zine. 
            # it might either be target + '.smd' or target + '/index.smd'
            # whatever we have to append, we append to target_file. 
            # but instead .smd, we append .md and instead of /index.smd, we 
            # append /README.md or just '/'
            search_target = target
            if target.startswith('/'):
                search_target = target[1:]
            search_smd = os.path.join(self.workspace, 'content', search_target + '.smd')
            search_index = os.path.join(self.workspace, 'content', search_target, 'index.smd')
            if os.path.exists(search_smd):
                # we link to an smd file
                target_file += '.md'
            elif os.path.exists(search_index):
                if not target_file or target_file.endswith('/'):
                    sep = '/'
                    if not target_file:
                        sep = ''
                    target_file += f'{sep}README.md' # link to a directory
                    # linking to directory rather than README.md is safer if the
                    # latter doesn't exist; it will still work in GH

            if target_dir:
                target_dir = f'{target_dir}/'
            new_target = f'{target_dir}{target_file}{anchor}'
        else:
            new_target = anchor

        link_url = f'[{link_text}]({new_target})'
        self.actions.append(TranslateLinkAction(source_file=relative_path,
                                                original=original,
                                                destination=new_target))
        return link_url

    # TODO: this is temp until loris fixes zine
    def rewrite_image_link(self, relative_path, img_text, img_target):
        assert False, "There shouldn't be any ![image](links) until zine is fixed"
        # new_target = f"[{img_text}]($image.url('{img_target}'))"
        # self.actions.append(TranslateImageAction(source_file=relative_path,
        #                                         original=img_target,
        #                                         destination=new_target))
        # return new_target

    def rewrite_content(self, markdown_content:str, relative_path:str) -> str:
        """
        - rewrites markdown links
        - but ignores image links ![imgtext](imglink)
        - also handles newlines in links
        """
    
        def handle_link(match: re.Match[str]) -> str:
            # Replace newlines in link text with spaces
            link_text = match.group(1).replace('\n', ' ')
            # Get the link target and strip any extra whitespace
            target = match.group(2).strip()  
            if target.startswith('http'):
                # Return the original link if it's a web URL
                return match.group(0)  
            else:
                # Rewrite the link if it's not an HTTP URL
                rewritten_link = self.rewrite_link(relative_path, link_text, target)
                return rewritten_link

        def handle_image_link(match: re.Match[str]) -> str:
            img_text = match.group(1).replace('\n', ' ')
            # Get the image target and strip any extra whitespace
            img_target = match.group(2).strip()
            # Rewrite the image link using the rewrite_image_link function
            rewritten_image_link = self.rewrite_image_link(relative_path,
                                                           img_text, img_target)
            return rewritten_image_link
        
        # do the image links first, because handle_link creates some
        rewritten_content = self.image_link_pattern.sub(handle_image_link, markdown_content)
        # Replace all links in the markdown content using the handle_link function
        rewritten_content = self.link_pattern.sub(handle_link, rewritten_content)
        # now the images
        return rewritten_content

    def split_yaml_and_content(self, content: str, smd_src_file: str) -> Tuple[str, str]:
        """
        Takes the content, splits it into the YAML section and the content 
        section, and then returns the two: yaml, content in a tuple
        """
        _ = self
        lines_smd = []
        lines_md = []
        seen_first_sep = False
        seen_second_sep = False
        for line in content.split('\n'):
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
            raise RuntimeError(f"ERROR: did not produce any YAML lines for {smd_src_file}")
        yaml = '\n'.join(lines_smd)
        content = '\n'.join(lines_md)
        return yaml, content




def usage_and_exit():
    print("Usage: python processor.py EDIT|COMMIT SMD_DIR MD_DIR WORKSPACE_DIR [--dry-run]")
    print("The first parameter MODE defines the conversion direction:")
    print("EDIT   : creates the WORKSPACE for editing")
    print("COMMIT : converts back to the GitHub representation, for committing")
    print()
    print("Example: python processor.py EDIT content zml/docs WORKSPACE --dry-run")
    sys.exit(1)


def main(args):
    if len(args) < 4:
        usage_and_exit()

    mode = args[0].lower()
    if mode not in ('edit', 'commit'):
        usage_and_exit()

    smd_dir = args[1]
    if not os.path.exists(smd_dir):
        print(f"ERROR: {smd_dir} does not exist")
        sys.exit(1)

    md_dir = args[2]
    if not os.path.exists(md_dir):
        print(f"ERROR: {md_dir} does not exist")
        sys.exit(1)

    workspace = args[3]
    if not os.path.exists(workspace):
        if mode == 'edit':
            print(f"WARNING: {workspace} does not exist. It will be created.")
        else:
            print(f"ERROR: {workspace} does not exist.")
            sys.exit(1)

    dry_run = False
    if len(args) > 4:
        dry_run = args[4].lower()

    Processor = Github2Zine if mode == 'edit' else Zine2Github
    processor = Processor(md_dir, smd_dir, workspace, dry_run)
    processor.process()
    # now log the results
    sep = '\n  - '
    print(f'Performed Actions:{sep}', end='')
    print(sep.join([str(a) for a in processor.actions]))


if __name__ == '__main__':
    main(sys.argv[1:])
