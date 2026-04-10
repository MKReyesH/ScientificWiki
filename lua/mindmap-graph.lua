function Div(el)
  if el.classes:includes("mindmap-graph") then
    
    local raw_text = pandoc.utils.stringify(el)
    local nodes = {}
    local links = {}
    local added_nodes = {}
    
    local function escape_js(str)
      return str:gsub("'", "\\'")
    end
    
    local function add_node(id, url, group)
      if not added_nodes[id] then
        local url_str = url and string.format("'%s'", escape_js(url)) or "null"
        table.insert(nodes, string.format("{ id: '%s', url: %s, group: %d }", escape_js(id), url_str, group))
        added_nodes[id] = true
      end
    end

    for line in string.gmatch(raw_text, "[^\r\n]+") do
      local source, target = string.match(line, "(.-)%s*->%s*(.*)")
      
      if source and target then
        add_node(source, nil, 1)

        if string.match(target, "^auto:") then
          local folder = string.match(target, "^auto:(.*)")
          local handle = io.popen('ls ' .. folder .. '/*.qmd 2>/dev/null')
          
          if handle then
            local result = handle:read("*a")
            handle:close()
            
            for filepath in string.gmatch(result, "[^\r\n]+") do
              local filename = string.match(filepath, "([^/]+)%.qmd$")
              local title = filename
              
              local f = io.open(filepath, "r")
              if f then
                local content = f:read("*a")
                f:close()
                local t = string.match(content, "title:%s*'([^']+)'") 
                       or string.match(content, 'title:%s*"([^"]+)"') 
                       or string.match(content, "title:%s*([^\n\r]+)")
                if t then title = t end
              end
              
              local url = folder .. "/" .. filename .. ".html"
              add_node(title, url, 2)
              table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(title)))
            end
          end
        else
          add_node(target, nil, 1)
          table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(target)))
        end
      end
    end
    
    local nodes_js = table.concat(nodes, ",\n        ")
    local links_js = table.concat(links, ",\n        ")
    
    -- The new, significantly cleaner JavaScript
    local html_code = [[
<div id="obsidian-graph" style="width: 100%; height: 600px; border: 1px solid #ddd; background: #fafafa; border-radius: 8px;"></div>

<script src="https://unpkg.com/force-graph"></script>
<script>
  const graphData = {
    nodes: [ ]] .. nodes_js .. [[ ],
    links: [ ]] .. links_js .. [[ ]
  };

  const Graph = ForceGraph()(document.getElementById('obsidian-graph'))
    .graphData(graphData)
    .linkDirectionalParticles(2)
    .nodeCanvasObject((node, ctx, globalScale) => {
      // 1. Set font size that scales smoothly as you zoom
      const label = node.id;
      const fontSize = 14 / globalScale;
      ctx.font = `${fontSize}px Sans-Serif`;
      
      // 2. Calculate the background box size based on text length
      const textWidth = ctx.measureText(label).width;
      const bckgDimensions = [textWidth, fontSize].map(n => n + fontSize * 0.4);

      // 3. Draw a crisp white box behind the text
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);

      // 4. Draw the actual text over the box
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = node.group === 1 ? '#555' : '#4285F4'; 
      ctx.fillText(label, node.x, node.y);

      // Save hitbox dimensions for hovering/clicking
      node.__bckgDimensions = bckgDimensions; 
    })
    .nodePointerAreaPaint((node, color, ctx) => {
      // Create the invisible hover/click area matching the text box size
      ctx.fillStyle = color;
      const bckgDimensions = node.__bckgDimensions;
      bckgDimensions && ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);
    })
    .onNodeClick(node => {
      if (node.url) window.location.href = node.url;
    });
</script>
    ]]
    
    return pandoc.RawBlock("html", html_code)
  end
end