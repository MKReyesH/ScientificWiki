import re
import sys
import os
import glob

def convert_latex_to_quarto(text):

    # --- 1. HIDE CODE BLOCKS ---
    code_blocks = []
    
    def hide_code(match):
        code_blocks.append(match.group(0))
        return f"__CODE_BLOCK_PLACEHOLDER_{len(code_blocks) - 1}__"
    
    # Matches triple backticks, then single backticks (preventing line-jumping bugs)
    text = re.sub(r'(```.*?```|`[^`\n]+`)', hide_code, text, flags=re.DOTALL)

    # --- 2. PERFORM LATEX REPLACEMENTS ---

    # Verbatim
    text = re.sub(r'\\verb(.)(.*?)\1', r'`\2`', text)

    # Sections
    text = re.sub(r'\\section\{([^}]+)\}', r'# \1', text)
    text = re.sub(r'\\subsection\{([^}]+)\}', r'## \1', text)
    text = re.sub(r'\\subsubsection\{([^}]+)\}', r'### \1', text)

    # Text Formatting
    text = re.sub(r'\\textbf\{([^}]+)\}', r'**\1**', text)
    text = re.sub(r'\\textit\{([^}]+)\}', r'*\1*', text)

    # Links
    text = re.sub(r'\\href\{([^}]+)\}\{([^}]+)\}', r'[\2](\1)', text)

    # Citations
    def cite_repl(match):
        keys = [k.strip() for k in match.group(1).split(',')]
        return f"[{'; '.join(['@' + k for k in keys])}]"
    text = re.sub(r'\\cite\{([^}]+)\}', cite_repl, text)

    # References
    def ref_repl(match):
        label = match.group(1).replace(':', '-')
        return f"@{label}"
    text = re.sub(r'\\(?:eq)?ref\{([^}]+)\}', ref_repl, text)

    # Equations
    def eq_repl(match):
        body = match.group(1)
        label_match = re.search(r'\\label\{([^}]+)\}', body)
        if label_match:
            label = label_match.group(1).replace(':', '-')
            body = re.sub(r'\\label\{[^}]+\}\s*', '', body)
            return f"$$\n{body.strip()}\n$$ {{#{label}}}"
        else:
            return f"$$\n{body.strip()}\n$$"
    text = re.sub(r'\\begin\{(?:equation|align)\*?\}(.*?)\\end\{(?:equation|align)\*?\}', eq_repl, text, flags=re.DOTALL)

    # --- NEW: NESTED LIST PARSING ---
    list_stack = [] # Tracks our current depth and list type
    
    def list_repl(match):
        token = match.group(0)
        stripped = token.strip()
        
        # Track depth dynamically
        if stripped.startswith('\\begin{itemize}'):
            list_stack.append('itemize')
            return ""
        elif stripped.startswith('\\begin{enumerate}'):
            list_stack.append('enumerate')
            return ""
        elif stripped.startswith('\\end{itemize}') or stripped.startswith('\\end{enumerate}'):
            if list_stack:
                list_stack.pop()
            return ""
        
        # Inject correct spaces and marker based on current depth
        elif stripped.startswith('\\item'):
            depth = max(0, len(list_stack) - 1)
            indent = "  " * depth # 2 spaces per depth level
            marker = "- " if list_stack and list_stack[-1] == 'itemize' else "1. "
            return indent + marker
            
        return token

    # Matches \begin, \end, and \item anywhere, capturing leading spaces and trailing empty lines
    list_pattern = r'^[ \t]*\\begin\{(?:itemize|enumerate)\}[ \t]*\n?|^[ \t]*\\end\{(?:itemize|enumerate)\}[ \t]*\n?|\\begin\{(?:itemize|enumerate)\}|\\end\{(?:itemize|enumerate)\}|^[ \t]*\\item[ \t]*|\\item[ \t]*'
    text = re.sub(list_pattern, list_repl, text, flags=re.MULTILINE)

    # Figures
    def fig_repl(match):
        body = match.group(1)
        
        path_match = re.search(r'\\includegraphics(?:\[([^\]]+)\])?\{([^}]+)\}', body)
        caption_match = re.search(r'\\caption\{([^}]+)\}', body)
        label_match = re.search(r'\\label\{([^}]+)\}', body)
        
        path = path_match.group(2) if path_match else "MISSING_PATH"
        options = path_match.group(1) if path_match and path_match.group(1) else ""
        caption = caption_match.group(1) if caption_match else ""
        
        attr_str = ""
        if options:
            w_match = re.search(r'width=([^,\]]+)', options)
            if w_match:
                attr_str += f' width="{w_match.group(1).strip()}"'
                
            h_match = re.search(r'height=([^,\]]+)', options)
            if h_match:
                attr_str += f' height="{h_match.group(1).strip()}"'
                
        tag = ""
        if label_match:
            lbl = label_match.group(1).replace(':', '-')
            tag = f"{{#{lbl}{attr_str}}}"
        elif attr_str:
            tag = f"{{{attr_str.strip()}}}"

        return f"![{caption}]({path}){tag}"

    text = re.sub(r'\\begin\{figure\}(?:\[.*?\])?(.*?)\\end\{figure\}', fig_repl, text, flags=re.DOTALL)

    # --- 3. RESTORE CODE BLOCKS ---
    for i, code in enumerate(code_blocks):
        text = text.replace(f"__CODE_BLOCK_PLACEHOLDER_{i}__", code)

    return text

if __name__ == "__main__":
    # AUTOMATION FIX: Automatically finds and updates all .qmd files recursively.
    files_to_process = glob.glob("doc/**/*.qmd", recursive=True)

    if not files_to_process:
        print("No .qmd files found to process.")
        sys.exit(0)

    for filepath in files_to_process:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        converted_content = convert_latex_to_quarto(content)
        
        # This overwrites the file safely on the GitHub Action runner (does not alter your main branch)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(converted_content)
            
        print(f"Processed and updated: {filepath}")