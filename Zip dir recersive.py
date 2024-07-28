import subprocess
import shutil
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from common.functions import *
from image_to_JPG_XL_converter import preset_paths, convert_to_dict, display_options, get_dir_path, total_time_taken

def zip_dir(source_dir_path, destination_zip_file_path):
    global folders; folders["submitted"] += 1
    
    logging.debug(f"Zip: '{source_dir_path}' -> '{destination_zip_file_path}'")
    process = subprocess.run(["7z", "a", "-r", "-mx0", "-tzip", destination_zip_file_path, source_dir_path], stderr=subprocess.PIPE, stdout=subprocess.PIPE)
    
    if process.returncode != 0:
        logging.error(f"stderr: {process.stderr.decode('utf-8')}")

def validate_and_cleanup(dir_path, zip_file_path):
    global folders
    
    if zip_file_path.exists() and dir_path.exists():
        folders["zipped"] += 1
        shutil.rmtree(dir_path)
    elif not zip_file_path.exists():
        folders["errored"] += 1
        logging.error(f"{zip_file_path} - Failed to create zip file")

def process_dir(dir_path):
    dir_to_process = {}
    
    for root, dirs, files in Path(dir_path).walk(top_down=False):
        for dir in dirs:
            subdir_path = root / dir
            zip_file_path = Path(f"{subdir_path}.zip")
            
            # Exludes the folders 1 level down from the root directory path 
            if subdir_path.parent != dir_path:
                dir_to_process[subdir_path] = zip_file_path
    
    with tqdm(total=len(dir_to_process), unit="dirs") as pbar:
        for subdir_path, zip_file_path in dir_to_process.items():
            zip_dir(subdir_path, zip_file_path)
            validate_and_cleanup(subdir_path, zip_file_path)
            pbar.update()

def main():
    create_text_file(preset_paths_text_file_path)
    
    lines = preset_paths(preset_paths_text_file_path)
    options = convert_to_dict(lines)
    
    display_options(options)
    
    dir_path = get_dir_path(options, "Enter in the directory path containing the folders to zip or input a number corresponding to the preset path: ")

    log_dir = Path.home().joinpath(r"Documents\_Logs\7-Zip")
    current_time = datetime.now().strftime("Date=%Y-%m-%d & Time=%H.%M.%S")
    logger = setup_logger(log_path=fr"{log_dir}\7-Zip log - {current_time}.log", logging_level_console="INFO")
    
    timer = total_time_taken(); next(timer)
    
    global folders; folders = {"submitted": 0, "zipped": 0, "errored": 0}
    
    process_dir(dir_path)
    
    hours, minutes, seconds = next(timer)

    logging.info(f"Total folders submitted: {folders['submitted']} , zipped: {folders['zipped']}")
    logging.info(f"Total elapsed time: {hours} hours, {minutes} minutes, {seconds} seconds")
    
if __name__ == "__main__":
    preset_paths_text_file_path = f"{__file__} - Preset directories.txt"
    
    while True:
        main()
