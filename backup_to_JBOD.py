import shutil
from pathlib import Path
import re
import time
from datetime import datetime
import logging
import filecmp
import concurrent.futures
import threading
from functools import partial
from common.functions import date_time, setup_logger, initalize_excel_file, get_files_and_folders
from image_to_JPG_XL_converter import total_time_taken, release_logger_handlers
    
def display_counter(interval: int|float=0.5):
    global counter
    global display_counter_status
    while display_counter_status:
        print(f"Checks: {counter["checked"]}, Copied: {counter["copied"]}, Errors: {counter["errored"]}, Moves: {counter["moved"]}, Removed: {counter["removed"]}, Updated: {counter["updated"]}", end='\r')
        time.sleep(interval)

def increment_counter(key: str, value: int=1):
    global counter
    with lock:
        counter[key] += value
        
def format_dest_dir(dir):
    return re.sub(r"(\\\\[0-9.]+\\)(disk)\d+(.*)", r'\1\2\3', dir)

def get_available_dirs(disks: int, dir):
    # Gets all the available directories in the different disks
    source_dirs = []
    
    for i in range(1, disks+1):
        formatted_dir = Path(re.sub(r"(\\\\[0-9.]+\\)(disk)(.*)", fr'\1\g<2>{i}\3', str(dir)))
        if formatted_dir.exists():
            source_dirs.append(formatted_dir)
    
    return source_dirs

def file_folder_match_and_mismatch_executor(max_workers: int, source_dir, dest_dir):
    global source_files_match, source_files_mismatch, source_dirs_match, source_dirs_mismatch
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        for root, dirs, files in dest_dir.walk():
            file_futures = [executor.submit(file_folder_match_and_mismatch, root, file, source_dir, dest_dir, source_files_match, source_files_mismatch, "file") for file in files]
            dir_futures = [executor.submit(file_folder_match_and_mismatch, root, dir, source_dir, dest_dir, source_dirs_match, source_dirs_mismatch, "folder") for dir in dirs]
    concurrent.futures.wait(file_futures + dir_futures)

def file_folder_match_and_mismatch(root, file, source_dir, dest_dir, match: list, mismatch: list, type: str):
    file_path = root.joinpath(file)
    file_path_relative = file_path.relative_to(dest_dir)
    source_file_path = source_dir.joinpath(file_path_relative)

    # First checks if source file/folder exsits then compares destination to source file/folder
    if (type == "file" and source_file_path.exists() and compare_file(source_file_path, file_path)) or (type == "folder" and source_file_path.exists()):
        # Check the file and destination files metadata matches and copy metadata over if not
        update_metadata(source_file_path, file_path)
        
        with lock:
            match.append(source_file_path)
    else:
        with lock:
            mismatch.append(file_path)
    increment_counter("checked")

def compare_file(source_file, target_file, compare_mode="size"):
    if compare_mode == "byte":
        return filecmp.cmp(source_file, target_file)
    elif compare_mode == "size":
        return True if source_file.stat().st_size == target_file.stat().st_size else False
    
def compare_metadata(source_file, target_file):
    return source_file.stat().st_mtime == target_file.stat().st_mtime

def update_metadata(source_file, target_file):
    if not compare_metadata(source_file, target_file):
        shutil.copystat(source_file, target_file)
        
        if compare_metadata(source_file, target_file):
            logging.info(f"Updated metadata: '{source_file}' -> '{target_file}'.")
            increment_counter("updated")
        else:
            logging.error(f"Updated metadata: '{source_file}' -> '{target_file}'.")
            increment_counter("errored")

def move_file_folder(item_path, dest_dir):
    try:
        disk_num = re.search(r"(\\\\[.\d]+\\)(disk)(\d+)(.*)", str(item_path)).group(3)
    except Exception as e:
        increment_counter("errored")
        logging.error(f"{item_path}: {e}"); return
    
    dest_dir_with_disk_num = re.sub(r"(\\\\[.\d]+\\)(disk)(.*)", fr"\1\g<2>{disk_num}\3", str(dest_dir))
    
    backup_dir_path = Path(f"{dest_dir_with_disk_num} [Backup]") / Path(datetime.now().strftime("%d-%m-%Y"))
    
    item_path_rel_path = Path(item_path).relative_to(dest_dir_with_disk_num) 
    item_path_dest = backup_dir_path / item_path_rel_path
    item_path_dest.parent.mkdir(parents=True, exist_ok=True)
    
    shutil.move(item_path, item_path_dest)
    
    verify_file_folder_move(item_path, item_path_dest)

def verify_file_folder_move(item_path, item_path_dest):
    if item_path_dest.exists() and not item_path.exists():
        logging.info(f"Move: File '{item_path}' -> '{item_path_dest}'.")
        increment_counter("moved")
    else:
        logging.error(f"Move: File '{item_path}' -> '{item_path_dest}'.")
        increment_counter("errored")

def remove_file_folder(item_path):
    item_path = Path(item_path)
    
    item_path.unlink() if item_path.is_file() else item_path.rmdir()
    
    if item_path.exists():
        logging.error(f"Remove: File '{item_path}'")
        increment_counter("errored")
    else:
        logging.info(f"Remove: File '{item_path}'")
        increment_counter("removed")
    
def get_available_disks(disks: int):
    source_dirs = {}
    for i in range(1, disks+1):
        source_dir = Path(fr"\\192.168.0.5\disk{i}\data")
        if source_dir.exists():
            source_dirs.update({f"disk{i}": [source_dir]})
    return source_dirs

def disks_free_space(data: dict):
    for key, value in data.items():
        data[key].append(shutil.disk_usage(value[0]).free)

def most_free_disk(data: dict):
    max_key = None
    max_value = -float('inf')
    
    for key, value in data.items():
        if value[1] > max_value:
            max_value = value[1]
            max_key = key
    return max_key

def copy_file_folder(item_path, source_dir, dest_dir, target_disk):
    item_path = Path(item_path)
    
    item_parent_relative_to_path = item_path.parent.relative_to(source_dir)
    
    formatted_dest_dir = Path(re.sub(r"(\\\\[0-9.]+\\)(disk)(.*)", fr'\g<1>{target_disk}\3', str(dest_dir)))
    
    item_path_dest = formatted_dest_dir / item_parent_relative_to_path / item_path.name; item_path_dest.parent.mkdir(parents=True, exist_ok=True)
    
    shutil.copy2(item_path, item_path_dest)
    
    verify_file_folder_copy(item_path, item_path_dest)
    
def verify_file_folder_copy(file_path, file_path_dest):
    if file_path_dest.exists() and ((file_path_dest.is_file() and compare_file(file_path, file_path_dest)) or file_path_dest.is_dir()):
        logging.info(f"Copy: File '{file_path}' -> '{file_path_dest}'.")
        increment_counter("copied")
    else:
        logging.error(f"Copy: File '{file_path}' -> '{file_path_dest}'.")
        increment_counter("errored")
    
def sync_files(source_dir, dest_dir, disks: int, log_file_path: str, backup_dir: bool=True, max_transfers: int=4):
    source_dir = Path(source_dir)
    if not source_dir.exists():
        return
    
    dest_dir = Path(format_dest_dir(dest_dir))
    
    print(f"Syncing source directory '{source_dir}' -> '{dest_dir}'")
    
    timer = total_time_taken(); next(timer)
    
    logger = setup_logger(
        log_path=log_file_path, 
        logging_level_console="CRITICAL", 
        logging_level_file="DEBUG"
    )
    
    global counter
    counter = {
        "checked": 0,
        "errored": 0,
        "moved": 0,
        "copied": 0,
        "removed": 0,
        "updated": 0
    }
    
    global display_counter_status; display_counter_status = True
    thread = threading.Thread(target=display_counter, args=(0.5,))
    thread.start()
    
    global source_files_match, source_files_mismatch, source_dirs_match, source_dirs_mismatch
    source_files_match, source_files_mismatch, source_dirs_match, source_dirs_mismatch = ([] for _ in range(4))
    
    dest_dirs = get_available_dirs(disks=disks, dir=dest_dir)
    # Running the dest_dirs in parallel, get all destination directory files and directories that match and mismatch the source directory files and folders
    with concurrent.futures.ThreadPoolExecutor(max_workers=disks) as executor:
        futures = [executor.submit(file_folder_match_and_mismatch_executor, max_workers=1000, source_dir=source_dir, dest_dir=dir) for dir in dest_dirs]
        concurrent.futures.wait(futures)
    
    # Get list of files/folders from the source directory
    source_files, source_dirs = get_files_and_folders(source_dir)
    
    # Source files not in destination directory
    missing_source_files = list(set(source_files).difference(set(source_files_match)))
    # Source directory not in destination directory
    missing_source_dirs = list(set(source_dirs).difference(set(source_dirs_match)))
    
    # From the destination directory move the mismatched files and directories to backup directory
    for item_paths in [source_files_mismatch, source_dirs_mismatch]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_transfers) as executor:
            if backup_dir:
                futures = [executor.submit(move_file_folder, item_path, dest_dir) for item_path in item_paths]
            else:
                futures = [executor.submit(remove_file_folder, item_path) for item_path in item_paths]
            concurrent.futures.wait(futures)
    
    # From source directory copy missing source files and directories to destination directory
    available_disk_paths = get_available_disks(disks)
    disks_free_space(available_disk_paths) 
    for item_paths in [missing_source_files, missing_source_dirs]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_transfers) as executor:
            futures = []
            
            for item_path in item_paths:
                target_disk = most_free_disk(available_disk_paths)
                
                if item_path.is_file():
                    # Subtract the target disk's free space from the size of the copied file.
                    available_disk_paths[target_disk][1] -= item_path.stat().st_size
                
                futures.append(executor.submit(copy_file_folder, item_path, source_dir, dest_dir, target_disk))
            concurrent.futures.wait(futures)
    
    display_counter_status = False
    thread.join()
    
    hours, minutes, seconds = next(timer); formatted_time_taken = f"{hours}h, {minutes}mins, {seconds}s"
    checks = len(source_files + source_dirs)
    total_stats = f"Checks: {checks}, Copied: {counter["copied"]}, Errors: {counter["errored"]}, Moves: {counter["moved"]}, Removed: {counter["removed"]}, Updated: {counter["updated"]}"
    
    logging.info(f"Elapsed time: {formatted_time_taken}, {total_stats}")
    
    release_logger_handlers(logger)
    
    return f"{formatted_time_taken}, {total_stats}"

def sync_files_batch(sync_files_data: dict, sync_files_default: partial, date_time_instance, log_dir):
    sync_files_data["folder1"] = sync_files_default(
        source_dir = r"D:\folder1",
        dest_dir = r"\\192.168.0.5\disk\tank\folder1",
        log_file_path = fr"{log_dir}\folder1 - Date={date_time_instance.YMD()} & Time={date_time_instance.HMS()}.log",
    )
    
    sync_files_data["folder2"] = sync_files_default(
        source_dir = r"D:\folder2",
        dest_dir = r"\\192.168.0.5\disk\tank\folder2",
        log_file_path = fr"{log_dir}\folder2 - Date={date_time_instance.YMD()} & Time={date_time_instance.HMS()}.log",
    )

if __name__ == "__main__":
    lock = threading.Lock()
    log_dir = Path.home() / "Logs"
    date_time_instance = date_time()
    max_file_transfers = 4
    disks = 9
    
    timer = total_time_taken(); next(timer)
    
    sync_files_data = {}
    
    sync_files_data["Date"] = datetime.now().strftime('%Y-%m-%d')
    sync_files_data["Total time taken"] = None
    
    sync_files_default = partial(sync_files, disks = disks, backup_dir = True, max_transfers = max_file_transfers)
    
    sync_files_batch(sync_files_data, sync_files_default, date_time_instance, log_dir)
    
    hours, minutes, seconds = next(timer)
    formatted_time_taken = f"{hours}h {minutes}mins {seconds}s"
    
    sync_files_data["Total time taken"] = formatted_time_taken
    
    excel_file_path = Path.home() / "Logs\sync_overview.xlsx"
    excel_file_headers = [key for key in sync_files_data.keys()]
    
    workbook, sheet = initalize_excel_file(excel_file_path=excel_file_path, excel_file_headers=excel_file_headers)
    
    synced_data = [value for value in sync_files_data.values()]
    
    sheet.append(synced_data)
    workbook.save(excel_file_path)
