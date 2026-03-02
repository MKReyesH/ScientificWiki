-- latex-to-quarto.lua

local function normalize_label(lbl)
  return lbl:gsub("^eq:", "eq-")
            :gsub("^fig:", "fig-")
            :gsub("^tab:", "tbl-")
            :gsub("^sec:", "sec-")
end

-- 1. EQUATION TARGETS: Just fix the label natively inside the Math block
function Math(el)
  if el.mathtype == 'DisplayMath' then
    el.text = el.text:gsub("\\label{([^}]+)}", function(lbl)
      local q_label = normalize_label(lbl)
      if not q_label:match("^eq%-") then q_label = "eq-" .. q_label end
      return "\\label{" .. q_label .. "}"
    end)
  end
  return el
end

-- 2. LINKS AND CITATIONS: Generate the Quarto syntax parsed as AST nodes
function RawInline(el)
  if el.format == 'tex' or el.format == 'latex' then
    local text = el.text

    -- \eqref{...} -> Renders as (1)
    local eqref_lbl = text:match("^\\eqref{([^}]+)}%s*$")
    if eqref_lbl then
      local q_label = normalize_label(eqref_lbl)
      if not q_label:match("^eq%-") then q_label = "eq-" .. q_label end
      local doc = pandoc.read("([-@" .. q_label .. "])", 'markdown')
      return doc.blocks[1].content
    end

    -- \ref{...} -> Renders as 1 (prefix suppressed to avoid double prefixes)
    local ref_lbl = text:match("^\\ref{([^}]+)}%s*$")
    if ref_lbl then
      local q_label = normalize_label(ref_lbl)
      local doc = pandoc.read("[-@" .. q_label .. "]", 'markdown')
      return doc.blocks[1].content
    end

    -- \cite{...} -> Renders citations
    local cite_lbl = text:match("^\\cite{([^}]+)}%s*$")
    if cite_lbl then
      local q_cites = cite_lbl:gsub("%s+", ""):gsub(",", "; @")
      local doc = pandoc.read("[@" .. q_cites .. "]", 'markdown')
      return doc.blocks[1].content
    end

    -- Pass other inline LaTeX to standard reader
    local doc = pandoc.read(text, 'latex')
    if doc.blocks and #doc.blocks > 0 and doc.blocks[1].t == "Para" then
      return doc.blocks[1].content
    end
  end
  return el
end

-- 3. FIGURE TARGETS AND STRUCTURAL BLOCKS
function RawBlock(el)
  if el.format == 'tex' or el.format == 'latex' then
    local text = el.text

    -- Explicitly extract and convert \begin{figure} to Quarto Markdown
    if text:match("\\begin{figure}") then
      local caption = text:match("\\caption{([^}]+)}") or ""
      local label = text:match("\\label{([^}]+)}") or ""
      
      local q_label = normalize_label(label)
      if q_label ~= "" and not q_label:match("^fig%-") then 
         q_label = "fig-" .. q_label 
      end

      -- Extract path and optional arguments (e.g., width)
      local args, path = text:match("\\includegraphics%[([^%]]+)%]{([^}]+)}")
      if not path then
        path = text:match("\\includegraphics{([^}]+)}")
        args = ""
      end

      if path then
        -- Convert LaTeX arguments (width=4cm) to Quarto arguments (width="4cm")
        local q_args = ""
        if args and args ~= "" then
          q_args = args:gsub("([%w_]+)=([^,%s]+)", '%1="%2"')
        end

        -- Construct the exact single-line Markdown you requested
        local md_str = "![" .. caption .. "](" .. path .. "){#" .. q_label .. " " .. q_args .. "}"
        local doc = pandoc.read(md_str, 'markdown')
        return doc.blocks
      end
    end

    -- For everything else, normalize labels and pass to Pandoc
    local clean_tex = text:gsub("\\label{([^}]+)}", function(lbl)
      return "\\label{" .. normalize_label(lbl) .. "}"
    end)
    local doc = pandoc.read(clean_tex, 'latex')
    return doc.blocks
  end
  return el
end