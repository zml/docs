# docs

## REQUIREMENTS:

- zig 0.14.0

## HOW TO EDIT WITH LIVE-PREVIEW & COMMIT DOCS

```console
zig build tool -- clone          # clones zml into the current directory (gitignored)
zig build tool -- edit           # prepares a WORKSPACE dir for editing
zig build tool -- build serve    # builds the zine website and serves it
```

Now, you can edit all `.smd` files, as well as `.shtml` layouts, assets in the
`./WORKSPACE` directory, while live-viewing on `https://127.0.0.1:1990`.

### ^^^ YOU EDIT IN ./WORKSPACE !!!

### HOWTO Links

Only ever use the following link notation to link to other docs:

```markdown
[blah][/folder/doc]  # no extension, start with /
[back to the root index](/)
[some tutorial](/tutorials/foo)
```


### HOWTO Images

**For multi-repo reasons, we never serve images from the `assets/` folder**.
They wouldn't show up on GitHub!

Instead, we upload them into the `docs-assets/` folder of the
[zml.github.io website repo](https://github.com/zml/zml.github.io/).

Until Zine is fixed (Loris is working on it), use the following notation for
images:

```markdown
[blah]($image.url('https://zml.ai/docs-assets/image.png'))
```

Once it is fixed, normal image urls, starting with `https://` will work again.
From then on, we can disable image-link-translation.


## COMMITTING

When you're done editing, run in the root dir of this repo:

```console
zig build tool -- commit
```

The above will split the YAML header and content from
`WORKSPACE/content/.../*.smd` files:

- YAML will go into `.smd` files in this repo, in `content/.../*.smd`
- Markdown content will go into `.md` files in the zml repo in
  `zml/docs/content/.../*.md`

So you need to (add and) commit both repos:

- `git commit` : this repo: `.smd`, assets, layouts
- `git commit -C zml` : `.md` Markdown content

To help you with that, `zig build tool -- commit` will run a `git status` in
both repos at the end.

```
zig build tool -- commit
Content scan took 1ms
info: COMMIT in ./WORKSPACE/
info: Performed Actions
info: - ProcessingFile{ .filename="WORKSPACE/content/misc/zml_api.smd", }
info: - SplitSmd{ .source_file="WORKSPACE/content/misc/zml_api.smd", .smd_dest="content/misc/zml_api.smd", .md_dest="zml/docs/misc/zml_api.md", }
info: - ProcessingFile{ .filename="WORKSPACE/content/misc/style_guide.smd", }
info: - SplitSmd{ .source_file="WORKSPACE/content/misc/style_guide.smd", .smd_dest="content/misc/style_guide.smd", .md_dest="zml/docs/misc/style_guide.md", }

...


======================================================================
Changes in this repo:
======================================================================
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   content/misc/index.smd

no changes added to commit (use "git add" and/or "git commit -a")



======================================================================
Changes in zml repo:
======================================================================
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   docs/content/misc/index.md

no changes added to commit (use "git add" and/or "git commit -a")
```

### NOTE:

- The `.smd` files are the authoritative source of existence,
      meaning: if there is no `.smd` file in `./contents/`, its associated
      `.md` file from the `zml` repo will not move into the workspace.

You can use above as a feature, adding `.md` files that are intended only for
GH browsing use, even in the `content/` directory; although, I'd advise against
such shenanigans.

**NOTE 2:**

- if you ever need to remove or rename a file in the docs:
- you must `rm`/`mv` it in both:
    - this repo: `./content/`
    - and the zml repo: `./zml/docs/content/`


## HACKING

- `build.zig` : builds all prerequisites, runs `tool` or tests

- `tools/tool.zig` : the main cmdline interface:

```
Usage: zig build tool -- command [opts]

Commands in order:
-1: help               : prints this help message
 0: clone [gitref]     : clones zml and optionally checks out gitref
 1: edit               : creates and prepares the WORKSPACE for editing
 2: build [serve ...]  : builds the (edited) website and optionally runs the dev server
 3: commit             : prepares the WORKSPACE for committing
```

- `tools/processor.zig` : translates between markdown and supermarkdown, called
  from `tool` (above)

- `tools/shell.zig` : little helpers do to shell scripty things

- `tools/regex.zig` : PCRE2 regex search / replace helpers for Markdown link
  replacements.

