import os
import shutil
import zipfile
import re

version = "1.0.0"

# create dist folder
if os.path.exists("dist"):
    shutil.rmtree("dist")

dist_folder = "dist/"
autorun_folder = "reframework/autorun/"
fonts_folder = "reframework/fonts/"

os.makedirs(dist_folder + autorun_folder)
os.makedirs(dist_folder + fonts_folder)

# copy files
shutil.copy("item_editor.lua", dist_folder + autorun_folder + "item_editor.lua")
shutil.copy(
    "fonts/SourceHanSansCN-Regular.otf",
    dist_folder + fonts_folder + "SourceHanSansCN-Regular.otf",
)

# create zip archive
archive = zipfile.ZipFile(
    f"dist/ref-mhws-item-editor-v{version}.zip", "w", zipfile.ZIP_DEFLATED
)

archive.write(
    dist_folder + autorun_folder + "item_editor.lua", autorun_folder + "item_editor.lua"
)
archive.write(
    dist_folder + fonts_folder + "SourceHanSansCN-Regular.otf", fonts_folder + "SourceHanSansCN-Regular.otf"
)

archive.close()
