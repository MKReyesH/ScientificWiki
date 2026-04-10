function CodeBlock(el)
  if el.classes:includes("mindmap-graph") then
    
    local raw_text = el.text
    local nodes = {}
    local links = {}
    local added_nodes = {}
    
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

    -- 1. Get the current execution path (Linux environment)
    local pwd_handle = io.popen("pwd")
    local current_dir = pwd_handle and pwd_handle:read("*l") or "Unknown"
    if pwd_handle then pwd_handle:close() end

    -- 2. Grab Quarto's Project Root variable and calculate relative depth
    local project_root = os.getenv("QUARTO_PROJECT_DIR") or current_dir

    local subpath = ""
    if #current_dir > #project_root then
        subpath = current_dir:sub(#project_root + 2)
    end

    local depth = 0
    if #subpath > 0 then
        local _, slashes = subpath:gsub("/", "")
        depth = slashes + 1
    end

    local rel_prefix = string.rep("../", depth)

    for line in string.gmatch(raw_text, "[^\r\n]+") do
      local source, target = string.match(line, "(.-)%s*->%s*(.*)")
      
      if source and target then
        source = source:match("^%s*(.-)%s*$")
        target = target:match("^%s*(.-)%s*$")
        
        add_node(source, nil, 1)

        if string.match(target, "^auto:") then
          local folder = string.match(target, "^auto:(.*)"):match("^%s*(.-)%s*$"):gsub("/$", "")
          local os_target_dir = project_root .. "/" .. folder
          
          local cmd = 'ls -1 "' .. os_target_dir .. '" 2>/dev/null'
          local handle = io.popen(cmd)
          local files_found = false
          
          if handle then
            local result = handle:read("*a")
            handle:close()
            
            for filename in string.gmatch(result, "[^\r\n]+") do
              if filename:match("%.qmd$") then
                files_found = true
                local title = filename
                local filepath = os_target_dir .. "/" .. filename
                
                local f = io.open(filepath, "r")
                if f then
                  local content = f:read("*a")
                  f:close()
                  local t = string.match(content, "title:%s*'([^']+)'") 
                         or string.match(content, 'title:%s*"([^"]+)"') 
                         or string.match(content, "title:%s*([^\n\r]+)")
                  if t then title = t:match("^%s*(.-)%s*$") end
                end
                
                local url = rel_prefix .. folder .. "/" .. filename:gsub("%.qmd$", ".html")
                add_node(title, url, 2)
                table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(title)))
              end
            end
          end
          
          if not files_found then
            local err_node = "[Missing: " .. folder .. "]"
            add_node(err_node, nil, 3) 
            table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(err_node)))
          end
          
        else
          add_node(target, nil, 1)
          table.insert(links, string.format("{ source: '%s', target: '%s' }", escape_js(source), escape_js(target)))
        end
      end
    end
    
    if #nodes == 0 then
      return pandoc.RawBlock("html", "<div style='padding: 20px; border: 2px solid red; color: red;'><strong>Graph Build Error:</strong> No nodes were found.</div>")
    end
    
    local nodes_js = table.concat(nodes, ",\n        ")
    local links_js = table.concat(links, ",\n        ")
    
    local html_code = [[
<div id="]] .. graph_id .. [[" style="width: 100%; height: 600px; border: 1px solid #ddd; background: #ffffff; border-radius: 8px;"></div>

<script src="https://unpkg.com/force-graph"></script>
<script>
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
      .linkColor(() => '#cccccc')
      .nodeCanvasObject((node, ctx, globalScale) => {
        const label = node.id;
        const fontSize = 14 / globalScale;
        ctx.font = `bold ${fontSize}px Sans-Serif`;
        
        const textWidth = ctx.measureText(label).width;
        const bckgDimensions = [textWidth, fontSize].map(n => n + fontSize * 1.2);

        let bgColor = '#f4f4f5';
        let borderColor = '#d4d4d8';
        let textColor = '#3f3f46';

        if (node.group === 2) { 
            bgColor = '#e0f2fe';
            borderColor = '#38bdf8';
            textColor = '#0369a1';
        } else if (node.group === 3) { 
            bgColor = '#fee2e2';
            borderColor = '#f87171';
            textColor = '#991b1b';
        }

        ctx.fillStyle = bgColor;
        ctx.strokeStyle = borderColor;
        ctx.lineWidth = 1.5 / globalScale;

        ctx.beginPath();
        const x = node.x - bckgDimensions[0] / 2;
        const y = node.y - bckgDimensions[1] / 2;
        const w = bckgDimensions[0];
        const h = bckgDimensions[1];
        const r = 6 / globalScale; 
        
        if (ctx.roundRect) {
            ctx.roundRect(x, y, w, h, r);
        } else {
            ctx.rect(x, y, w, h); 
        }
        
        ctx.fill();
        ctx.stroke();

        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = textColor; 
        ctx.fillText(label, node.x, node.y);

        node.__bckgDimensions = bckgDimensions; 
      })
      .nodePointerAreaPaint((node, color, ctx) => {
        ctx.fillStyle = color;
        const bckgDimensions = node.__bckgDimensions;
        if (bckgDimensions) {
            ctx.fillRect(node.x - bckgDimensions[0] / 2, node.y - bckgDimensions[1] / 2, ...bckgDimensions);
        }
      })
      .onNodeHover(node => {
        container.style.cursor = node && node.url ? 'pointer' : null;
      })
      .onNodeClick(node => {
        if (node.url) {
            window.location.href = node.url;
        }
      });
  })();
</script>
    ]]
    
    return pandoc.RawBlock("html", html_code)
  end
end