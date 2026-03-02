-- Helper: Normalizes LaTeX colons to Quarto hyphens (e.g., "fig:1" -> "fig-1")
local function normalize_label(lbl)
  return lbl:gsub("^eq:", "eq-")
            :gsub("^fig:", "fig-")
            :gsub("^tab:", "tbl-")
            :gsub("^tbl:", "tbl-")
            :gsub("^sec:", "sec-")
end

-- 1. Handle Display Equations and their \label{} tags
function Math(el)
  if el.mathtype == 'DisplayMath' then
    local label = el.text:match("\\label{([^}]+)}")
    
    if label then
      -- Strip the \label{} command from the math content
      local clean_math = el.text:gsub("\\label{[^}]+}%s*", "")
      
      -- Normalize and ensure the label starts with Quarto's "eq-" prefix
      local q_label = normalize_label(label)
      if not q_label:match("^eq%-") then
         q_label = "eq-" .. q_label
      end
      
      -- Output the exact Markdown syntax Quarto expects
      return pandoc.RawInline('markdown', "$$\n" .. clean_math .. "\n$$ {#" .. q_label .. "}")
    end
  end
  return el
end

-- 2. Handle Inline LaTeX commands (\ref, \eqref, \cite, \textbf, etc.)
function RawInline(el)
  if el.format == 'tex' or el.format == 'latex' then
    local text = el.text

    -- A. Intercept \eqref{...} -> Renders as (1)
    local eqref_lbl = text:match("^\\eqref{([^}]+)}%s*$")
    if eqref_lbl then
      local q_label = normalize_label(eqref_lbl)
      if not q_label:match("^eq%-") then 
        q_label = "eq-" .. q_label 
      end
      -- The parentheses go outside the Quarto [-@...] syntax
      return pandoc.RawInline('markdown', "([-@" .. q_label .. "])")
    end

    -- B. Intercept \ref{...} -> Renders as 1
    local ref_lbl = text:match("^\\ref{([^}]+)}%s*$")
    if ref_lbl then
      local q_label = normalize_label(ref_lbl)
      -- We don't force 'eq-' here because this could be pointing to a figure or table!
      return pandoc.RawInline('markdown', "[-@" .. q_label .. "]")
    end

    -- C. Intercept \cite{...} -> Renders as [@cite1; @cite2]
    local cite_lbl = text:match("^\\cite{([^}]+)}%s*$")
    if cite_lbl then
      -- Handles comma-separated multiple citations natively
      local q_cites = cite_lbl:gsub("%s+", ""):gsub(",", "; @")
      return pandoc.RawInline('markdown', "[@" .. q_cites .. "]")
    end

    -- D. Pass all other inline LaTeX (like \textbf{}) to Pandoc's internal translator
    local doc = pandoc.read(text, 'latex')
    if doc.blocks[1] and doc.blocks[1].t == "Para" then
      return doc.blocks[1].content
    end
  end
  return el
end

-- 3. Handle Structural LaTeX Blocks (\section{}, \begin{itemize}, etc.)
function RawBlock(el)
  if el.format == 'tex' or el.format == 'latex' then
    -- Pass the entire block to Pandoc's internal translator
    local doc = pandoc.read(el.text, 'latex')
    return doc.blocks
  end
  return el
end