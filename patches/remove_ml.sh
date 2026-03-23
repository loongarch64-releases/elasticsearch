#!/bin/bash

src=$1
ver_num=$2

# ================================================
# 自动扫描并移除与 ml 模块直接或间接相关的插件
# ================================================
INSERT_BLOCK="insert_block.tmp"

# 1. 初始 ml 相关依赖关键字列表
ml_related_list=(":x-pack:plugin:ml" "ml")

# 2. 待处理目录
pending_screening_list=(
    "x-pack/plugin"
    "test/external-modules"
)

# 3. 记录已处理的插件，避免重复处理
skipped_plugins_list=(":x-pack:plugin:ml")
echo "  if (dir.name == 'ml' && path.startsWith(':x-pack:plugin')) return;" >> "$INSERT_BLOCK"
modified_gradle_files=()

# 4. 必须/非必须依赖的关键字
STRONG_DEPS="api|implementation|compileOnly|runtimeOnly|compile|runtime"
WEAK_DEPS="testImplementation|testRuntimeOnly|testCompileOnly|itImplementation|testCompile|itCompile|clusterPlugins|clusterModules"

echo "开始扫描 ml 相关依赖..."
continue_scanning=true
iteration=1
while [ "$continue_scanning" = true ]; do
    echo "[ ROUND $iteration ] ..."
    continue_scanning=false
    
    # 遍历待查目录
    for search_dir in "${pending_screening_list[@]}"; do
        if [ ! -d "$src/$search_dir" ]; then continue; fi
        # 查找所有 build.gradle 文件
        while read -r gradle_file; do 
            # 获取当前插件的相对路径
            rel_path=${gradle_file#$src/}
            dir_path=$(dirname "$rel_path")
            # 转换路径为 Gradle 格式
            plugin_gradle_path=":${dir_path//\//:}"
            plugin_name=$(basename "$dir_path")
            
            # 如果该插件已经在跳过列表中，则跳过检查
            is_skipped=false
            for skipped_p in "${skipped_plugins_list[@]}"; do
                if [[ "$plugin_gradle_path" == "$skipped_p" ]] || [[ "$plugin_gradle_path" == "$skipped_p":* ]]; then
                    is_skipped=true
                    break
                fi
            done
            if [ "$is_skipped" = true ]; then
                continue
            fi

            # 遍历 ml 相关依赖关键字列表
            for ml_item in "${ml_related_list[@]}"; do
                # 检查 build.gradle 文件中是否包含该关键字
                if grep -qE "['\"]$ml_item['\"]" "$gradle_file"; then
                    line_content=$(grep -E "['\"]$ml_item['\"]" "$gradle_file")
                    
                    # 若为必须依赖 --> 完整跳过该插件
                    if echo "$line_content" | grep -qE "$STRONG_DEPS"; then
                        echo "  [强依赖] $plugin_gradle_path 依赖于 $ml_item"
                        # 构造插件的跳过逻辑
                        parent_gradle_path=${plugin_gradle_path%:$plugin_name}
                        echo "  if (dir.name == '$plugin_name' && path.startsWith('$parent_gradle_path')) return;" >> "$INSERT_BLOCK"
                        
                        # 更新 ml 列表，任何依赖此插件的插件也将被处理
                        if [[ ! " ${ml_related_list[@]} " =~ " ${plugin_gradle_path} " ]]; then
                            ml_related_list+=("$plugin_gradle_path")
                            ml_related_list+=("$plugin_name")
                            continue_scanning=true
                        fi
                        
                        skipped_plugins_list+=("$plugin_gradle_path")
                        break
                        
                    elif echo "$line_content" | grep -qE "$WEAK_DEPS"; then
                        # 若为非必须依赖 --> 仅删除该依赖
                        echo "  [弱依赖] 从 $rel_path 中移除对 $ml_item 的依赖"
                        sed -i "/['\"]$ml_item['\"]/d" "$gradle_file"
                        
                        if [[ ! " ${modified_gradle_files[@]} " =~ " ${rel_path} " ]]; then
                            modified_gradle_files+=("${rel_path}")
                        fi
                    fi
                fi
            done
        done < <(find "$src/$search_dir" -name "build.gradle")
    done
    ((iteration++))

    # 防止死循环
    if [ $iteration -gt 20 ]; then break; fi
done

# 4. 应用补丁到 settings.gradle
if [ -f "$INSERT_BLOCK" ]; then
    # 去重
    sort -u "$INSERT_BLOCK" -o "$INSERT_BLOCK"
    
    # 插入到 settings.gradle 的 addSubProjects 函数开头
    sed -i "/void addSubProjects(String path, File dir) {/r $INSERT_BLOCK" "$src/settings.gradle"
    echo ">>> 已将跳过逻辑注入 settings.gradle"
    rm -f "$INSERT_BLOCK"
fi

# 5. 特殊处理
if [ "$ver_num" -ge 8016000 ]; then
    sed -i "s|'benchmarks',|//'benchmarks',|" "$src/settings.gradle"
    sed -i '/clusterPlugins project(/,/)$/d' "$src/x-pack/plugin/inference/qa/mixed-cluster/build.gradle"
fi

# 6. 总结
echo "=========== ml 适配处理 =============="
echo "1. 完整跳过的插件数量: ${#skipped_plugins_list[@]}"
for p in "${skipped_plugins_list[@]}"; do echo "   - $p"; done

echo "2. 修改了依赖的 Gradle 文件数量: ${#modified_gradle_files[@]}"
for f in "${modified_gradle_files[@]}"; do echo "   - $f"; done
echo "======================================"

echo "org.gradle.dependency.verification=off" >> "$src/gradle.properties"


