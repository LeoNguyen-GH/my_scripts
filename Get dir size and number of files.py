from common.functions import *
from image_to_JPG_XL_converter import total_time_taken
import concurrent.futures
from pathlib import Path
import time
import threading
import re

def increment_counter(key: str, value: int=1):
    global counter
    with lock:
        counter[key] += value
        
def format_dir(dir):
    return re.sub(r"([A-Za-z]:\\)(.*)", r'\2', dir)

def get_available_dirs(total_disks: int, dir):
    # Gets all the available directories in the found disk shares
    available_dirs = []
    
    for i in range(1, total_disks+1):
        formatted_dir = Path(re.sub(r"(\\\\[0-9.]+\\)(disk)(.*)", fr'\1\g<2>{i}\3', str(dir)))
        if formatted_dir.exists():
            available_dirs.append(formatted_dir)
    
    return available_dirs

def display_counter(interval: int|float=0.5):
    global counter
    global display_counter_status
    while display_counter_status:
        print(f"Total files: {counter['total files']}, size: {bytes_unit_conversion(counter['files total byte size'])} ({counter['files total byte size']})", end='\r')
        time.sleep(interval)

def dir_executor(dir_path):
    with concurrent.futures.ThreadPoolExecutor(max_workers=3000) as executor:
        for root, dirs, files in dir_path.walk():
            futures = [executor.submit(increment_total_file_and_size, root / file) for file in files]
            concurrent.futures.wait(futures)

def increment_total_file_and_size(file_path):
    increment_counter("total files")
    increment_counter("files total byte size", file_path.stat().st_size)

def main():
    unraid_array_total_disks = 5
    unraid_server_ip = "192.168.0.2"
    unraid_user_share = "share1"
    global counter; counter = {
        "files total byte size": 0,
        "total files": 0
    }
    
    user_input = input(r"Input the UNRAID directory path to parse its total files and size (e.g. P:\folder1, folder1): ").strip(' "')
    formatted_dir = format_dir(user_input)
    fully_formatted_dir = Path(fr"\\{unraid_server_ip}\disk\{unraid_user_share}") / formatted_dir
    
    disk_share_dirs = get_available_dirs(total_disks=unraid_array_total_disks, dir=fully_formatted_dir)
    
    timer = total_time_taken()
    next(timer)
    
    global display_counter_status; display_counter_status = True
    thread = threading.Thread(target=display_counter, args=(0.5,))
    thread.start()
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=unraid_array_total_disks) as executor:
        futures = [executor.submit(dir_executor, dir) for dir in disk_share_dirs]
        concurrent.futures.wait(futures)
    
    display_counter_status = False
    thread.join()
    
    hours, minutes, seconds = next(timer)
    formatted_time_taken = f"{hours}h {minutes}mins {seconds}s"
    
    converted_bytes = bytes_unit_conversion(counter["files total byte size"])
    
    print(f"Total files: {counter['total files']}, size: {converted_bytes} ({counter['files total byte size']})")
    print(f"Elapsed time: {formatted_time_taken}")
    
if __name__ == "__main__":
    lock = threading.Lock()
    main()
