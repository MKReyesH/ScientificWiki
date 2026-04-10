function CodeBlock(el)
  if el.classes:includes("mindmap-graph") then
    
    local raw_text = el.text
    local nodes = {}
    local links = {}
    local added_nodes = {}
    
    -- Generate a unique ID for the graph container
    local graph_id = "graph_" .. tostring(math.random(100000, 999999))
    
    local function escape_js(str)
      if not str then return "Unknown" end
      return str:gsub("'", "\\'")
    end
    
    local function add_node(id, url, group)
      if not id or id == "" then return end
      if not added_nodes[id] then
        local url_str = url and string.format("'%s'", escape_js(url)) or "null"
        table.insert(nodes, string.format("{ id: '%s', url: %s, group: %d }", escape_js(id), url_str, group))
        added_nodes[id] = true
      end
    end

    for line in string.gmatch(raw_text, "[^\r\n]+") do
      local source, target = string.match(line, "(.-)%s*->%s*(.*)")
      
      if source and target then
        -- Clean up any invisible trailing spaces
        source = source:match("^%s*(.-)%s*$")
        target = target:match("^%s*(.-)%s*$")
        
        add_node(source, nil, 1)

        if string.match(target, "^auto:") then
          local folder = string.match(target, "^auto:(.*)")
          folder = folder:match("^%s*(.-)%s*$")
          
          -- Cross-Platform OS Detection (Fixes Windows/Mac/Linux crashes)
          local is_windows = package.config:sub(1,1) == '\\'
          local cmd = 'ls "' .. folder .. '"/*.qmd 2>/dev/null'
          if is_windows then
            cmd = 'dir "' .. folder .. '\\*.qmd" /b /s 2>nul'
          end
          
          local handle = io.popen(cmd)
          if handle then
            local result = handle:read("*a")
            handle:close()
            
            for filepath in string.gmatch(result, "[^\r\n]+") do
              local filename = string.match(filepath, "([^/\\]+)%.qmd$")
              
              if filename then
                local title = filename
                
                -- Attempt to read YAML safely
                local f = io.open(filepath, "r")
                if f then
                  local content = f:read("*a")
                  f:close()
                  local t = string.match(content, "title:%s*'([^']+)'") 
                         or string.match(content, 'title:%s*"([^"]+)"') 
                         or string.match(content, "title:%s*([^\n\r]+)")
                  if t then title = t:match("^%s*(.-)%s*$") end
                end
                
                local url = folder .. "/" .. filename .. ".html"
                add_node(title, url, 2)
                table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(title)))
              end
            end
          end
        else
          add_node(target, nil, 1)
          table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(target)))
        end
      end
    end
    
    -- Visual Error Handler: If Lua failed to parse anything, tell the user instead of showing a blank screen
    if #nodes == 0 then
      return pandoc.RawBlock("html", "<div style='padding: 20px; border: 2px solid red; color: red; font-family: sans-serif; background: #ffe6e6; border-radius: 8px;'><strong>Graph Build Error:</strong> No nodes were found. Ensure you are using a Code Block with the <code>mindmap-graph</code> class and formatting lines as <code>Source -> Target</code>.</div>")
    end
    
    local nodes_js = table.concat(nodes, ",\n        ")
    local links_js = table.concat(links, ",\n        ")
    
    local html_code = [[
<div id="]] .. graph_id .. [[" style="width: 100%; height: 600px; border: 1px solid #ddd; background: #fafafa; border-radius: 8px;"></div>

<script src="https://unpkg.com/force-graph"></script>
<script>
  // Prevent JS Race Conditions: Wait until ForceGraph is fully loaded before drawing
  (function initGraph() {
    if (typeof ForceGraph === 'undefined') {
      setTimeout(initGraph, 50);
      return;
    }

    const graphData = {
      nodes: [ ]] .. nodes_js .. [[ ],
      links: [ ]] .. links_js .. [[ ]
    };

    const container = document.getElementById(']] .. graph_id .. [[');
    if (!container) return;

    const Graph = ForceGraph()(container)
      .graphData(graphData)
      .linkDirectionalParticles(2)
      .nodeCanvasObject((node, ctx, globalScale) => {
        const label = node.id;
        const fontSize = 14 / globalScale;
        ctx.font = `${fontSize}px Sans-Serif`;
        
        const textWidth = ctx.measureText(label).width;
        const bckgDimensions = [textWidth, fontSize].map(n => n + fontSize * 0.4);

        ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
        ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);

        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = node.group === 1 ? '#555' : '#4285F4'; 
        ctx.fillText(label, node.x, node.y);

        node.__bckgDimensions = bckgDimensions; 
      })
      .nodePointerAreaPaint((node, color, ctx) => {
        ctx.fillStyle = color;
        const bckgDimensions = node.__bckgDimensions;
        bckgDimensions && ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);
      })
      .onNodeClick(node => {
        if (node.url) window.location.href = node.url;
      });
  })();
</script>
    ]]
    
    return pandoc.RawBlock("html", html_code)
  end
end