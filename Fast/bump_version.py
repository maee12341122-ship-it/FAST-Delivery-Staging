import re

pubspec_path = "pubspec.yaml"

with open(pubspec_path, "r", encoding="utf-8") as f:
    content = f.read()

# البحث عن نمط الإصدار مثل version: 2.2.0+3
match = re.search(r'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)', content)

if match:
    version_name = match.group(1)
    build_number = int(match.group(2))
    new_build_number = build_number + 1
    
    new_version_line = f"version: {version_name}+{new_build_number}"
    new_content = content.replace(match.group(0), new_version_line)
    
    with open(pubspec_path, "w", encoding="utf-8") as f:
        f.write(new_content)
        
    print(f"✅ تم تحديث رقم البناء تلقائياً إلى: {version_name}+{new_build_number}")
else:
    print("❌ لم يتم العثور على صيغة الإصدار في ملف pubspec.yaml")
