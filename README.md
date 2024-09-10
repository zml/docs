# docs

## REQUIREMENTS: 

- python: only if you want to COMMIT changes
- bazel : for building zig docs
- zig : for building the docs with Zine

## HOWTO:

```console
./00-CLONE-ZML.sh
./01-PREPARE-FOR-EDITS.sh
./02-BUILD.sh serve
```

Now, you can edit all `.smd` files, as well as `.shtml` layouts, assets in WORKSPACE.

### ^^^ YOU EDIT IN ./WORKSPACE !!!

When you're done editing, run:

```console
./03-PREPARE-FOR-COMMIT.sh
```

The above will split the YAML header and content from `WORKSPACE/content/.../*.smd` files:

- YAML will go into `.smd` files in this repo, in `content/.../*.smd`
- Markdown content will go into `.md` files in the zml repo in `zml/docs/content/.../*.md`

So you need to commit both repos:

- `git commit` : this repo: `.smd`, assets, layouts
- `git commit -C zml` : `.md` Markdown content


**NOTE:** 

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
