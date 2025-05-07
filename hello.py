import os

text_extensions = {
    ".txt", ".md", ".yaml", ".yml", ".json", ".sh", ".py", ".go", ".js", ".ts",
    ".html", ".css", ".Dockerfile", ".conf", ".ini", ".xml", ".csv", ".tsv", ".sql"
}

output = []

for root, dirs, files in os.walk("."):
    for file in files:
        file_path = os.path.join(root, file)
        _, ext = os.path.splitext(file)

        # включаем dockerfile и файлы без расширения вручную
        if ext.lower() in text_extensions or file.lower() == "dockerfile":
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    content = f.read()
                output.append(f"# path: {file_path}\n{content}\n")
            except Exception as e:
                print(f"could not read {file_path}: {e}")

# сохраняем в файл
with open("project_files_dump.txt", "w", encoding="utf-8") as out:
    out.writelines(output)
