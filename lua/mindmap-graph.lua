function CodeBlock(el)
  if el.classes:includes("mindmap-graph") then
    
    local raw_text = el.text
    
    local edges = {}
    local nodes_set = {}
    local node_urls = {}
    local node_colors = {}
    local node_shapes = {}
    local node_groups = {} 

    local function parse_node_str(str)
        local name, attr_str = str:match("^(.-)%s*%{(.+)%}%s*$")
        if not name then
            name = str
            attr_str = ""
        end
        name = name:match("^%s*(.-)%s*$")
        
        local attrs = {}
        if attr_str ~= "" then
            for k, v in attr_str:gmatch("(%w+)%s*:%s*([^,]+)") do
                attrs[k] = v:match("^%s*(.-)%s*$")
            end
        end
        return name, attrs
    end

    local function register_node(id, attrs)
        if not id or id == "" then return end
        nodes_set[id] = true
        if attrs.url then node_urls[id] = attrs.url end
        if attrs.color then node_colors[id] = attrs.color end
        if attrs.shape then node_shapes[id] = attrs.shape end
        if attrs.group then node_groups[id] = attrs.group end
    end

    local function add_edge(src, tgt)
        table.insert(edges, {src = src, tgt = tgt})
    end

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

    for line in string.gmatch(raw_text, "[^\r\n]+") do
      local src_str, tgt_str = string.match(line, "(.-)%s*->%s*(.*)")
      
      if src_str and tgt_str then
        local src_name, src_attrs = parse_node_str(src_str)
        local tgt_name, tgt_attrs = parse_node_str(tgt_str)
        
        register_node(src_name, src_attrs)

        if string.match(tgt_name, "^auto:") then
          local folder = tgt_name:match("^auto:(.*)"):gsub("/$", "")
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
                
                local auto_url = rel_prefix .. folder .. "/" .. filename:gsub("%.qmd$", ".html")
                register_node(title, { url = auto_url, color = tgt_attrs.color, shape = tgt_attrs.shape })
                add_edge(src_name, title)
              end
            end
          end
          
          if not files_found then
            local err_node = "[Missing/Empty: " .. folder .. "]"
            register_node(err_node, { group = 3 }) 
            add_edge(src_name, err_node)
          end
          
        else
          register_node(tgt_name, tgt_attrs)
          add_edge(src_name, tgt_name)
        end
      else
        local name, attrs = parse_node_str(line)
        if name and name ~= "" then
            register_node(name, attrs)
        end
      end
    end
    
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
    for node, deg in pairs(in_degree) do
        if deg == 0 then
            table.insert(queue, node)
            node_depths[node] = 0
        end
    end
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

    local function escape_js(str)
      if not str then return "Unknown" end
      return str:gsub("'", "\\'")
    end

    local nodes_js_arr = {}
    for node in pairs(nodes_set) do
        local url_str = node_urls[node] and string.format("'%s'", escape_js(node_urls[node])) or "null"
        local color_str = node_colors[node] and string.format("'%s'", escape_js(node_colors[node])) or "null"
        local shape_str = node_shapes[node] and string.format("'%s'", escape_js(node_shapes[node])) or "'rounded'"
        local grp = node_groups[node] or 1
        local dpt = node_depths[node] or 0 
        
        table.insert(nodes_js_arr, string.format("{ id: '%s', url: %s, group: %d, depth: %d, color: %s, shape: %s }", 
            escape_js(node), url_str, grp, dpt, color_str, shape_str))
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

    // Generates a true monochromatic contrast theme using HSL color shifting
    function getThemeColors(hexColor) {
        if (!hexColor) return { bg: '#ffffff', fg: '#000000' };
        
        let hex = hexColor.replace('#', '');
        if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
        const r = parseInt(hex.substr(0, 2), 16);
        const g = parseInt(hex.substr(2, 2), 16);
        const b = parseInt(hex.substr(4, 2), 16);
        
        // Convert RGB to HSL
        let rNorm = r / 255, gNorm = g / 255, bNorm = b / 255;
        let max = Math.max(rNorm, gNorm, bNorm), min = Math.min(rNorm, gNorm, bNorm);
        let h, s, l = (max + min) / 2;

        if (max === min) {
            h = s = 0; // achromatic
        } else {
            let d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
                case rNorm: h = (gNorm - bNorm) / d + (gNorm < bNorm ? 6 : 0); break;
                case gNorm: h = (bNorm - rNorm) / d + 2; break;
                case bNorm: h = (rNorm - gNorm) / d + 4; break;
            }
            h /= 6;
        }

        const yiq = ((r * 299) + (g * 587) + (b * 114)) / 1000;
        let targetL;
        
        if (yiq >= 140) {
            // Light background -> Make text/border a rich, dark version of the same hue
            targetL = Math.max(0.15, l - 0.5); 
            s = Math.min(1.0, s + 0.3); // Boost saturation slightly to prevent greying out
        } else {
            // Dark background -> Make text/border a bright, pastel version
            targetL = Math.min(0.95, l + 0.5); 
            s = Math.max(0.0, s - 0.1); 
        }

        // Convert HSL back to RGB
        let outR, outG, outB;
        if (s === 0) {
            outR = outG = outB = targetL;
        } else {
            const hue2rgb = (p, q, t) => {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 1/2) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            };
            let q = targetL < 0.5 ? targetL * (1 + s) : targetL + s - targetL * s;
            let p = 2 * targetL - q;
            outR = hue2rgb(p, q, h + 1/3);
            outG = hue2rgb(p, q, h);
            outB = hue2rgb(p, q, h - 1/3);
        }

        const fg = '#' + 
            Math.round(outR * 255).toString(16).padStart(2, '0') + 
            Math.round(outG * 255).toString(16).padStart(2, '0') + 
            Math.round(outB * 255).toString(16).padStart(2, '0');
            
        return { bg: hexColor, fg: fg };
    }

    const Graph = ForceGraph()(container)
      .graphData(graphData)
      .linkDirectionalParticles(2)
      .linkColor(() => '#cccccc')
      .nodeCanvasObject((node, ctx, globalScale) => {
        const label = node.id;
        const cappedDepth = Math.min(node.depth || 0, 4); 
        const baseFontSize = 16 - (cappedDepth * 2); 
        const fontSize = baseFontSize / globalScale;
        ctx.font = `bold ${fontSize}px Sans-Serif`;
        
        // Text Wrapping Algorithm
        const maxTextWidth = (130 - (cappedDepth * 8)) / globalScale; 
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

        // Compute Dimensions
        const lineHeight = fontSize * 1.2;
        const textWidth = Math.max(...lines.map(l => ctx.measureText(l).width));
        const padding = fontSize * 1.5;
        const boxW = textWidth + padding;
        const boxH = lines.length * lineHeight + padding;
        const maxDim = Math.max(boxW, boxH);
        
        // Hierarchical Base Colors
        const depthColors = ['#3b82f6', '#93c5fd', '#dbeafe', '#f1f5f9', '#f8fafc'];
        let baseColor = node.color || depthColors[cappedDepth];
        if (node.group === 3) baseColor = '#fee2e2'; // Error color

        // Generate True Monochromatic Theme
        const theme = getThemeColors(baseColor);

        // Styling
        ctx.fillStyle = theme.bg;
        ctx.strokeStyle = theme.fg;
        ctx.lineWidth = 1.5 / globalScale;

        // Draw Shape
        ctx.beginPath();
        const shape = node.shape || 'rounded';
        
        if (shape === 'circle') {
            ctx.arc(node.x, node.y, maxDim / 2, 0, 2 * Math.PI, false);
        } else if (shape === 'square') {
            ctx.rect(node.x - maxDim / 2, node.y - maxDim / 2, maxDim, maxDim);
        } else if (shape === 'box') {
            ctx.rect(node.x - boxW / 2, node.y - boxH / 2, boxW, boxH);
        } else {
            const r = (10 - cappedDepth) / globalScale; 
            if (ctx.roundRect) ctx.roundRect(node.x - boxW / 2, node.y - boxH / 2, boxW, boxH, r);
            else ctx.rect(node.x - boxW / 2, node.y - boxH / 2, boxW, boxH);
        }
        
        ctx.fill();
        ctx.stroke(); 

        // Draw Text
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = theme.fg; 
        
        const startY = node.y - (lines.length * lineHeight) / 2 + lineHeight / 2;
        lines.forEach((line, index) => {
             ctx.fillText(line, node.x, startY + index * lineHeight);
        });

        node.__shapeData = { shape, boxW, boxH, maxDim }; 
      })
      .nodePointerAreaPaint((node, color, ctx) => {
        ctx.fillStyle = color;
        const d = node.__shapeData;
        if (d) {
            ctx.beginPath();
            if (d.shape === 'circle') {
                ctx.arc(node.x, node.y, d.maxDim / 2, 0, 2 * Math.PI, false);
            } else if (d.shape === 'square') {
                ctx.rect(node.x - d.maxDim / 2, node.y - d.maxDim / 2, d.maxDim, d.maxDim);
            } else {
                ctx.rect(node.x - d.boxW / 2, node.y - d.boxH / 2, d.boxW, d.boxH);
            }
            ctx.fill();
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