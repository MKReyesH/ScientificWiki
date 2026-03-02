function Para(el)
  -- 1. Check if the paragraph contains exactly one element, and it's a RawInline
  if #el.content == 1 and el.content[1].t == "RawInline" then
    local raw = el.content[1]
    
    -- 2. Check if the RawInline is formatted as tex/latex
    if raw.format == "tex" or raw.format == "latex" then
      local text = raw.text
      
      -- 3. Check if it contains our equation
      if text:match("\\begin{equation}") then
        
        -- Extract the label
        local label = text:match("\\label{([^}]+)}")
        
        -- Strip out the LaTeX wrappers and the label to isolate the math string
        local math_content = text:gsub("\\begin{equation%*?}", "")
                                 :gsub("\\end{equation%*?}", "")
                                 :gsub("\\label{[^}]+}", "")
        
        -- Clean up extra whitespace/newlines
        math_content = math_content:gsub("^%s+", ""):gsub("%s+$", "")
        
        if label then
          -- Normalize the label (e.g., eq:secondorder -> eq-secondorder)
          local q_label = label:gsub(":", "-")
          if not q_label:match("^eq%-") then
            q_label = "eq-" .. q_label
          end
          
          -- 4. Rebuild the Paragraph exactly how Quarto expects it:
          -- [Math Node] + [Space] + [Str Node with {#eq-label}]
          return pandoc.Para({
            pandoc.Math('DisplayMath', math_content),
            pandoc.Space(),
            pandoc.Str("{#" .. q_label .. "}")
          })
        else
          -- If there's no label, just return the unnumbered math
          return pandoc.Para({
            pandoc.Math('DisplayMath', math_content)
          })
        end
      end
    end
  end
end