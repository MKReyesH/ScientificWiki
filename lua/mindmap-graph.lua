function CodeBlock(el)
  if el.classes:includes("mindmap-graph") then
    
    local raw_text = el.text
    
    -- We use these to build our logical map first
    local edges = {}
    local node_urls = {}
    local node_groups = {} 
    local nodes_set = {}

    local function register_node(id, url, group)
        if not id or id == "" then return end
        nodes_set[id] = true
        if url then node_urls[id] = url end
        if not node_groups[id] or group == 3 then
            node_groups[id] = group
        end
    end

    local function add_edge(src, tgt)
        table.insert(edges, {src = src, tgt = tgt})
    end

    -- 1. Setup paths
    local pwd_handle = io.popen("pwd")
    local current_dir = pwd_handle and pwd_handle:read("*l") or "Unknown"
    if pwd_handle then pwd_handle:close() end
    local project_root = os.getenv("QUARTO_PROJECT_DIR") or current_dir

    local subpath = ""
    if #current_dir > #project_root then
        subpath = current_dir:sub(#project_root + 2)
    end
    local depth_rel = 0
    if #subpath > 0 then
        local _, slashes = subpath:gsub("/", "")
        depth_rel = slashes + 1
    end
    local rel_prefix = string.rep("../", depth_rel)

    -- 2. Parse text and resolve 'auto:' links
    for line in string.gmatch(raw_text, "[^\r\n]+") do
      local source, target = string.match(line, "(.-)%s*->%s*(.*)")
      
      if source and target then
        source = source:match("^%s*(.-)%s*$")
        target = target:match("^%s*(.-)%s*$")
        
        register_node(source, nil, 1)

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
                register_node(title, url, 2)
                add_edge(source, title)
              end
            end
          end
          
          if not files_found then
            local err_node = "[Missing: " .. folder .. "]"
            register_node(err_node, nil, 3) 
            add_edge(source, err_node)
          end
          
        else
          register_node(target, nil, 1)
          add_edge(source, target)
        end
      end
    end
    
    -- 3. Calculate Graph Hierarchy (Depths)
    local in_degree = {}
    local out_edges = {}
    for node in pairs(nodes_set) do
        in_degree[node] = 0
        out_edges[node] = {}
    end
    for _, edge in ipairs(edges) do
        table.insert(out_edges[edge.src], edge.tgt)
        in_degree[edge.tgt] = in_degree[edge.tgt] + 1
    end

    local node_depths = {}
    local queue = {}
    -- Find roots (nodes with no incoming connections)
    for node, deg in pairs(in_degree) do
        if deg == 0 then
            table.insert(queue, node)
            node_depths[node] = 0
        end
    end
    -- Fallback in case every single node is in a closed loop (unlikely but safe)
    if #queue == 0 and next(nodes_set) then
        local first_node = next(nodes_set)
        table.insert(queue, first_node)
        node_depths[first_node] = 0
    end

    local head = 1
    while head <= #queue do
        local curr = queue[head]
        head = head + 1
        local current_depth = node_depths[curr]
        
        for _, neighbor in ipairs(out_edges[curr]) do
            if not node_depths[neighbor] then
                node_depths[neighbor] = current_depth + 1
                table.insert(queue, neighbor)
            end
        end
    end

    -- 4. Construct JS Data Arrays
    local function escape_js(str)
      if not str then return "Unknown" end
      return str:gsub("'", "\\'")
    end

    local nodes_js_arr = {}
    for node in pairs(nodes_set) do
        local url_str = node_urls[node] and string.format("'%s'", escape_js(node_urls[node])) or "null"
        local grp = node_groups[node] or 1
        local dpt = node_depths[node] or 0 
        table.insert(nodes_js_arr, string.format("{ id: '%s', url: %s, group: %d, depth: %d }", escape_js(node), url_str, grp, dpt))
    end

    local links_js_arr = {}
    for _, edge in ipairs(edges) do
        table.insert(links_js_arr, string.format("{ source: '%s', target: '%s' }", escape_js(edge.src), escape_js(edge.tgt)))
    end

    if #nodes_js_arr == 0 then
      return pandoc.RawBlock("html", "<div style='padding: 20px; border: 2px solid red; color: red;'><strong>Graph Build Error:</strong> No nodes were found.</div>")
    end
    
    local nodes_js = table.concat(nodes_js_arr, ",\n        ")
    local links_js = table.concat(links_js_arr, ",\n        ")
    
    local graph_id = "graph_" .. tostring(math.random(100000, 999999))
    
    -- Notice overflow:hidden and position:relative added to the div
    local html_code = [[
<div id="]] .. graph_id .. [[" style="width: 100%; height: 600px; border: 1px solid #ddd; background: #ffffff; border-radius: 8px; overflow: hidden; position: relative;"></div>

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
        
        // 1. Calculate sizing based on depth hierarchy
        const cappedDepth = Math.min(node.depth || 0, 4); // Max depth scaling capped at 4
        const baseFontSize = 18 - (cappedDepth * 2.5); // Roots get size 18, children scale down
        const fontSize = baseFontSize / globalScale;
        ctx.font = `bold ${fontSize}px Sans-Serif`;
        
        // 2. Text Wrapping Algorithm
        const maxTextWidth = (140 - (cappedDepth * 10)) / globalScale; 
        const words = label.split(' ');
        let lines = [];
        let currentLine = words[0];
        
        for (let i = 1; i < words.length; i++) {
            let word = words[i];
            let width = ctx.measureText(currentLine + " " + word).width;
            if (width < maxTextWidth) {
                currentLine += " " + word;
            } else {
                lines.push(currentLine);
                currentLine = word;
            }
        }
        lines.push(currentLine);

        // 3. Dynamic Shape Dimensions
        const lineHeight = fontSize * 1.2;
        const textWidth = Math.max(...lines.map(l => ctx.measureText(l).width));
        const padding = fontSize * 1.2;
        const bckgDimensions = [textWidth + padding, lines.length * lineHeight + padding];

        // 4. Color Hierarchy by Depth
        const palettes = [
            { bg: '#3b82f6', border: '#2563eb', text: '#ffffff' }, // Depth 0: Strong Blue
            { bg: '#93c5fd', border: '#3b82f6', text: '#1e3a8a' }, // Depth 1: Soft Blue
            { bg: '#dbeafe', border: '#93c5fd', text: '#1e40af' }, // Depth 2: Very Light Blue
            { bg: '#f1f5f9', border: '#cbd5e1', text: '#334155' }, // Depth 3: Light Slate
            { bg: '#f8fafc', border: '#e2e8f0', text: '#475569' }  // Depth 4+: Pale Slate
        ];
        
        let colors = palettes[cappedDepth];
        
        // Override style if it's an error node
        if (node.group === 3) { 
            colors = { bg: '#fee2e2', border: '#ef4444', text: '#991b1b' };
        }

        ctx.fillStyle = colors.bg;
        ctx.strokeStyle = colors.border;
        ctx.lineWidth = 1.5 / globalScale;

        // Draw Custom Rounded Rectangle
        ctx.beginPath();
        const x = node.x - bckgDimensions[0] / 2;
        const y = node.y - bckgDimensions[1] / 2;
        const w = bckgDimensions[0];
        const h = bckgDimensions[1];
        const r = (10 - cappedDepth) / globalScale; 
        
        if (ctx.roundRect) {
            ctx.roundRect(x, y, w, h, r);
        } else {
            ctx.rect(x, y, w, h); 
        }
        
        ctx.fill();
        ctx.stroke();

        // Draw Wrapped Text Lines
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = colors.text; 
        
        const startY = node.y - (lines.length * lineHeight) / 2 + lineHeight / 2;
        lines.forEach((line, index) => {
             ctx.fillText(line, node.x, startY + index * lineHeight);
        });

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

      // Responsive Observer to handle window resizing
      const resizeObserver = new ResizeObserver(entries => {
        for (let entry of entries) {
            Graph.width(entry.contentRect.width);
            Graph.height(entry.contentRect.height);
        }
      });
      resizeObserver.observe(container);

  })();
</script>
    ]]
    
    return pandoc.RawBlock("html", html_code)
  end
end