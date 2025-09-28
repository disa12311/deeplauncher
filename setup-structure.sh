#!/bin/bash
# setup-structure.sh - Ensure proper file structure for deployment

set -e

echo "🔧 Setting up project structure..."

# Ensure public directory exists
mkdir -p public

# Move index.html to public/ if it exists in root
if [ -f "index.html" ] && [ ! -f "public/index.html" ]; then
    echo "📁 Moving index.html to public/"
    mv index.html public/
fi

# Copy minecraft HTML files to public/ if they exist in root
for file in minecraft_1.8.html minecraft_1.12.html; do
    if [ -f "$file" ] && [ ! -f "public/$file" ]; then
        echo "📁 Moving $file to public/"
        mv "$file" "public/"
    fi
done

# Ensure WASM output directory exists in public
mkdir -p public/wasm/pkg

echo "✅ File structure setup complete!"
echo "📂 Structure:"
echo "├── public/"
echo "│   ├── index.html"
echo "│   ├── minecraft_1.8.html"
echo "│   ├── minecraft_1.12.html"
echo "│   └── wasm/pkg/ (WASM files will be here)"
echo "├── src/"
echo "│   ├── Cargo.toml"
echo "│   └── game_engine.rs"
echo "└── build.sh"