# docs

## REQUIREMENTS: 

- python: for translating smd <--> md
- zig 0.13.0: for building the docs with Zine

## HOW TO EDIT WITH LIVE-PREVIEW & COMMIT DOCS

```console
./00-CLONE-ZML.sh
./01-PREPARE-FOR-EDITS.sh
./02-BUILD.sh serve
```

Now, you can edit all `.smd` files, as well as `.shtml` layouts, assets in `./WORKSPACE`, while live-viewing on `https://localhost:1990`.

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
They wouldn't show up on github.

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
./03-PREPARE-FOR-COMMIT.sh
```

The above will split the YAML header and content from `WORKSPACE/content/.../*.smd` files:

- YAML will go into `.smd` files in this repo, in `content/.../*.smd`
- Markdown content will go into `.md` files in the zml repo in `zml/docs/content/.../*.md`

So you need to commit both repos:

- `git commit` : this repo: `.smd`, assets, layouts
- `git commit -C zml` : `.md` Markdown content

To help you with that, `./03-PREPARE-FOR-COMMIT.sh` will run a `git status` in
both repos at the end.

```
./03-PREPARE-FOR-COMMIT.sh
WORKSPACE/content/misc/zml_api.smd -> ./content/misc/zml_api.smd + zml/docs/content/misc/zml_api.md
...
WORKSPACE/content/index.smd -> ./content/index.smd + zml/docs/content/index.md



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

- the .smd files are the authoritative source of existence, 
      meaning: if there is no .smd file in `./contents/`, its associated
      `.md` file from the zml repo will not move into the workspace.

You can use above as a feature, adding .md files that are intended only for
GH browsing use, even in the content/ directory; although, I'd advise against
such shenanigans.

**NOTE 2:**

- if you ever need to remove a file in the docs, or rename it:
- you must mv it in both:
    - this repo: `./content/`
    - and the zml repo: `./zml/docs/content/`


## HACKING

This repository contains a collection of bash and python scripts. For python,
having the Python LSP running is recommended. For that reason, an environment
`env` is provided that provides the LSP.

To create the environment:

```console
python -m venv env
source ./env/bin/activate
pip install -r ./requirements_lsp.txt
```

After that, the environment is already activated and you can start your editor.

If you return to your work and need to activate the environment:

```console
source ./env/bin/activate
# and start the one and only true editor:
nvim
```

