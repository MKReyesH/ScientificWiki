function RawBlock(el)
  -- 1. Check if Pandoc classified this as a raw LaTeX block
  if el.format:match('tex') or el.format:match('latex') then
    
    -- 2. Check if the block contains a standalone equation environment
    if el.text:match('\\begin{equation}') then
      
      -- Extract the label (e.g., eq:secondorder)
      local label = el.text:match('\\label{([^}]+)}')
      
      -- Strip out the LaTeX environment wrappers and the label to isolate the math
      local inner_math = el.text:gsub('\\begin{equation}', '')
                                :gsub('\\end{equation}', '')
                                :gsub('\\label{[^}]+}', '')
      
      -- Clean up any excessive blank lines left behind
      inner_math = inner_math:gsub("^\n+", ""):gsub("\n+$", "")
      
      -- Format the label for Quarto (replace colon with hyphen)
      local q_label = ''
      if label then
        q_label = label:gsub(':', '-')
        -- Ensure it has the 'eq-' prefix Quarto expects
        if not q_label:match('^eq%-') then
          q_label = 'eq-' .. q_label
        end
      end
      
      -- 3. Construct the exact Markdown string Quarto needs
      local md_str = '$$\n' .. inner_math .. '\n$$ {#' .. q_label .. '}'
      
      -- 4. Parse this new string back into Pandoc AST blocks so Quarto processes it natively
      return pandoc.read(md_str, 'markdown').blocks
    end
  end
  
  -- Leave all other blocks untouched
  return nil
end