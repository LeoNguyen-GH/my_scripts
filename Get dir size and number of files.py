from common.functions import *
import concurrent.futures
from pathlib import Path
import queue
import time

while True:
    user_input = input("Input directory name: ").strip()
    if not user_input:
        continue
    disks = 7
    files, files_total_byte_size = queue.Queue(), queue.Queue()
    files_total_byte_size.put(0)
    bg_display_stop = 0
    
    def update_files_total_byte_size(size):
        current_size = files_total_byte_size.get()
        new_size = current_size + size
        files_total_byte_size.put(new_size)
    
    def available_disks(append_dir = None):
        source_dirs = []
        for i in range(1, disks+1):
            source_dir = Path(fr"\\192.168.11.1\disk{i}\Backup\{append_dir}") if append_dir else Path(fr"\\192.168.11.1\disk{i}\Backup")
            if source_dir.exists():
                source_dirs.append(source_dir)
        return source_dirs
    
    def submit_executor(function, item_list):
        with concurrent.futures.ThreadPoolExecutor(max_workers=disks) as executor:
            futures = [executor.submit(function, item) for item in item_list]
            executor.submit(bg_display(len(item_list)))
            concurrent.futures.wait(futures)
    
    def file_executor(directory):
        global bg_display_stop
        with concurrent.futures.ThreadPoolExecutor(max_workers=3000) as executor:
            for root, dirs, files in directory.walk():
                file_futures = [executor.submit(file_path_and_size, root, file) for file in files]
        concurrent.futures.wait(file_futures)
        bg_display_stop += 1
    
    def file_path_and_size(root, file):
        file_path = root.joinpath(file)
        files.put(file_path)
        update_files_total_byte_size(file_path.stat().st_size)
    
    def items_per_second():
        start_time = time.time()
        start_num_items = int(files.qsize())
        while True:
            elapsed_time = time.time() - start_time
            end_num_items = int(files.qsize()) - start_num_items
            if elapsed_time >= 1:
                items_per_second = end_num_items / elapsed_time
                print("Items added per second:", items_per_second)
                start_time = time.time()
                start_num_items = int(files.qsize())

    def bg_display(stop, polling_period = 0.5):
        global bg_display_stop
        prev_total_files = 0
        while bg_display_stop != stop:
            current_total_files = files.qsize()
            total_files_added = current_total_files - prev_total_files
            total_files_per_second = int((1/polling_period)*total_files_added)
            prev_total_files = current_total_files
            total_size = files_total_byte_size.queue[0]
            print(f"Total files: {current_total_files}, {total_files_per_second}it/s, Total size: {bytes_unit_conversion(total_size)} ({total_size:,} bytes)", end='\r')
            time.sleep(polling_period)

    start_time = time.time()
    
    disk_share_paths = available_disks(user_input)
    submit_executor(
        function = file_executor, 
        item_list = disk_share_paths
    )
    
    files, files_total_byte_size = list(files.queue), int(files_total_byte_size.get())
    
    converted_bytes = bytes_unit_conversion(files_total_byte_size)
    print(f"Total size of 'P:\\{user_input}': {converted_bytes} ({files_total_byte_size:,} bytes)")
    print(f"Total files: {len(files)}")
    print(f"Time elapsed: {elapsed_time(time.time() - start_time)}")