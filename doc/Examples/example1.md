---
title: 'How to write a page in Markdown'
---

Standard GitHub Pages can transform simple Markdown files (plain text files with a `.md` extension) into HTML webpages. For this wiki, we go a step further by using **Quarto**, a scientific publishing system that seamlessly handles complex equations, cross-referencing, and bibliography management. 

Quarto Markdown syntax is highly intuitive. Below are examples of the formatting you will use most often.

# This is a section

## This is a subsection

### This is a subsubsection

Section names are created by adding one or more `#` symbols followed by a space. Use `##` or `###` for subsections and sub-subsections, respectively.

### Mathematical Equations

You can write inline equations, such as $x^2+y^2=r^2$, by enclosing the formula in single `$` symbols. 

To write a standalone (unnumbered) equation on its own line, enclose it in double `$$` symbols:

$$
x=\frac{-b\pm \sqrt{b^2-4ac}}{2a} \,
$$

If you want to create a **labeled equation** that you can reference later, simply append `{#eq-yourlabel}` to the closing `$$`:

$$
x=\frac{-b\pm \sqrt{b^2-4ac}}{2a} \,
$$ {#eq-secondorder}

You can then easily reference this equation in your text by typing `@eq-secondorder`, which will automatically render as a clickable link (e.g., Equation @eq-secondorder).

### Text Formatting & Lists

You can make text *italic* or **bold** by enclosing it in single `*` or double `**` asterisks, respectively. 

Create an unordered list using the `-` symbol. The level of indentation determines the hierarchy of the list:

- Level 1 item
  - Level 2 item
  - Level 2 item
    - Level 3 item

For ordered lists, use numbers. You can actually just write `1.` for every item, and it will be automatically ordered correctly when the page renders:

1. First element
1. Second element
1. Third element

### Figures and tables

To insert a cross-referenced image with a controlled width, use the following syntax: 
`![Your caption text here](path_to_file.png){#fig-label width="80%"}`

![Default frog picture.](img/Examples/frog.png){#fig-frog width="80%"}

Markdown tables require a header row and a divider. The Quarto syntax allows you to easily add a caption and a label at the bottom:

| Column 1 | Column 2 | Column 3 |
|:---------|:---------|:---------|
| a        | b        | c        |
| d        | e        | f        |
: Table caption {#tbl-example}

### Blockquotes

To emphasize a quote or important note, use the `>` symbol at the start of the line:

> "If it is on the internet... it must be true." - Abraham Lincoln

Quarto also includes special **Callout Blocks** to draw attention to notes, warnings, or tips. You create them by opening and closing a block with three colons `:::` like this:

:::{.callout-note}
This is a helpful note! You can also use `.callout-warning`, `.callout-tip`, `.callout-caution`, or `.callout-important` to change the color and icon of the box.
:::

### Code Snippets

To format short `inline code` within a sentence, enclose the text in single backticks `` ` ``.

To insert multi-line blocks of code with syntax highlighting, enclose the block in triple backticks ```` ``` ````` and specify the programming language on the first line:

```cpp
int sum() {
  int a = 5;
  int b = 10;
  return a + b;
}
```

### Links and Citations

To insert a hyperlink, place the text in square brackets and the URL in parentheses:
[GitHub Repository](https://github.com/MKReyesH/ScientificWiki)

To cite a paper from our bibliography file, use the `@` symbol followed by the citation key inside square brackets. Multiple citations are separated by semicolons:
The expansion of the universe is accelerating [@riess1998; @perlmutter1999].