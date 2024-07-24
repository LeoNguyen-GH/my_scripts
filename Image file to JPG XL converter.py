import concurrent.futures
import subprocess
from pathlib import Path
import time
from collections import Counter
import uuid
from datetime import datetime
from tqdm import tqdm
from common.functions import *

def preset_paths(file_path):
    with open(file_path, mode="r", encoding="utf-8") as file:
        return file.read().splitlines()
        
def convert_to_dict(data_list):
    data = {}
    
    for index, item in enumerate(data_list):
        data[index+1] = item
    
    return data

def display_options(options: dict):
    for key, value in options.items():
        print(f"{key}. {value}")

def dir_path_prompt(options: dict):
    user_input = input("Enter in the directory path containing the images to convert to .jxl or input a number corresponding to the preset path: ").strip().strip('"')
    return Path(options[int(user_input)]) if user_input in str(options) else Path(user_input)

def is_dir_path_valid(dir_path):
    if not dir_path.exists() or not dir_path:
        printRed(f"The directory '{dir_path}' could not be found."); return False
    return True

def get_dir_path(options: dict):
    while True:
        dir_path = dir_path_prompt(options)
        
        if not is_dir_path_valid(dir_path):
            continue
        else:
            if user_choice(f"Do you confirm the target directory '{dir_path}' is correct? (Y/N): "):
                return dir_path

def filename_validation(file_name, file_path):
    try:
        file_name.encode('ascii'); return True
    except UnicodeEncodeError:
        logging.warning(f"{file_path} - Skipped (contains non-ASCII characters)"); return False

def processed_file_exist(file_path):
    if file_path.with_suffix(".jxl").exists():
        global img_counter; img_counter["skipped"] += 1
        logging.warning(f"{file_path} - Skipped (processed file path already exists)")
        return True

def undo_process(original_file_path, file_path, remove_file, log_error):
    # Preserve the original file if an error occured
    global img_counter; img_counter['errored'] += 1
    
    logging.error(log_error)
    
    logging.warning(f"{file_path} - Moving file back to its original location '{original_file_path}'.")
    file_path.rename(original_file_path)
    
    logging.warning(f"{remove_file} - Removing file.")
    remove_file.unlink(missing_ok=True)

def convert_img(original_file_path, source_file_path, destination_file_path):
    # Use CJXL to convert the moved image to a JXL image file
    try:
        subprocess.run(["cjxl", str(source_file_path), "--distance", "0", "--effort", "10", str(destination_file_path)], stderr=subprocess.PIPE, check=True)
        if not destination_file_path.exists():
            undo_process(original_file_path, source_file_path, destination_file_path, f"{original_file_path} - Processed file not found"); return False
        return True
    except (subprocess.CalledProcessError, Exception) as e:
        undo_process(original_file_path, source_file_path, destination_file_path, f"{original_file_path} - {e}"); return False

def decode_and_compare_img(source_file_path, processed_file_path):
    # decode the processed file
    decoded_processed_file_path = source_file_path.with_stem(source_file_path.stem + "_decoded")
    subprocess.run(["djxl", str(processed_file_path), str(decoded_processed_file_path)], stderr=subprocess.PIPE, check=True)

    # Compare decoded processed file and source file 
    compared_result = subprocess.run(['magick', 'compare', '-metric', 'ae', str(source_file_path), str(decoded_processed_file_path), 'NUL'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    decoded_processed_file_path.unlink()
    
    return compared_result

def process_result(result, file_path, source_file_path, processed_file_path):
    if result.returncode == 0:
        # Move processed file back to source file directory and remove the source file
        logging.debug(f"'{file_path}' - Done: magick compare returned {result.returncode}")
        
        global img_counter
        img_counter['original file sizes'] += source_file_path.stat().st_size
        img_counter['processed file sizes'] += processed_file_path.stat().st_size
        
        processed_file_path.rename(file_path.with_suffix('.jxl'))
        
        source_file_path.unlink()
        
        img_counter['processed'] += 1
    else:
        undo_process(file_path, source_file_path, processed_file_path, f"{file_path} - Failed: magick compare returned {result.returncode}")

def process_image(file_path, temp_dir_path):
    if processed_file_exist(file_path):
        return
    
    temp_dir_path.mkdir(parents=True, exist_ok=True)
    
    source_file_path = temp_dir_path.joinpath(file_path.stem + "_" + str(uuid.uuid4()) + file_path.suffix)
    processed_file_path = source_file_path.with_suffix('.jxl')

    logging.debug(f"'{file_path}' - Original File Name to '{source_file_path}' - Temporary File Name")

    # Move the image to the temporary directory. 
    file_path.rename(source_file_path) # Note: images are moved to the temp directory because CJXL is unable to handle certain characters if present in the file's path
    
    if not convert_img(file_path, source_file_path, processed_file_path):
        return

    compared_result = decode_and_compare_img(source_file_path, processed_file_path)
    
    process_result(compared_result, file_path, source_file_path, processed_file_path)

def total_time_taken():
    start_time = time.time()
    yield
    
    elapsed_time = time.time() - start_time
    hours, remainder = divmod(elapsed_time, 3600)
    minutes, seconds = divmod(remainder, 60)
    
    yield hours, minutes, seconds
    
def start_executor(dir_path, function, max_workers, temp_dir_path):
    global img_counter
    futures = []
    
    img_files = [file for file in list(dir_path.glob('**/*')) if file.is_file() and file.suffix.lower() in ('.png', '.jpg', '.jpeg') and filename_validation(file.name, file) and file.parent != temp_dir_path]
    
    with tqdm(total=len(img_files), unit="Img") as pbar:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                for file in img_files:
                    img_counter['submitted'] += 1
                    future = executor.submit(function, file, temp_dir_path)
                    future.add_done_callback(lambda p: pbar.update())
                    futures.append(future)
                
        concurrent.futures.wait(futures)

def calculate_space_saved(file_sizes_before: int, file_sizes_after: int):
    # Calculate size difference between original and processed directory
    size_diff = bytes_unit_conversion(file_sizes_before - file_sizes_after)
    
    # Calculate the difference between original and process directory in percentage terms
    percentage_processed_to_original = f"{(file_sizes_after / file_sizes_before) * 100:.3f}%"
    
    return size_diff, percentage_processed_to_original

def release_logger_handlers(logger):
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()
            
def main():
    create_text_file(preset_paths_text_file_path)
    
    lines = preset_paths(preset_paths_text_file_path)
    options = convert_to_dict(lines)
    
    display_options(options)
    
    dir_path = get_dir_path(options)
    
    max_workers = num_input(
        prompt = "Input the amount of images to process in parallel (Must be greater than 0): ",
        condition = lambda x: x > 0
    )
    
    log_dir = Path.home().joinpath(r"Documents\_Logs\Image to JXL converter"); current_date_time = datetime.now().strftime("Date=%Y-%m-%d & Time=%H.%M.%S")
    logger = setup_logger(
        log_path = fr"{log_dir}\{current_date_time}.log", 
        error_log_path = fr"{log_dir}\{current_date_time} - error log.log",
        logging_level_console = "INFO"
    )
    logging.getLogger('asyncio').disabled = True
    
    timer = total_time_taken(); next(timer)
    
    global img_counter
    img_counter = Counter({"submitted": 0, "processed": 0, "errored": 0, "skipped": 0, "original file sizes": 0, "processed file sizes": 0})
    temp_dir_path = dir_path.joinpath("_temp")
    
    start_executor(dir_path, process_image, max_workers, temp_dir_path)
    
    if temp_dir_path.exists():
        temp_dir_path.rmdir()
    
    hours, minutes, seconds = next(timer)

    size_diff, percentage = calculate_space_saved(img_counter["original file sizes"], img_counter["processed file sizes"])

    logging.info(f"Total images submitted: {img_counter['submitted']}, processed: {img_counter['processed']}, errored: {img_counter["errored"]}, skipped: {img_counter["skipped"]}")
    logging.info(f"Total space saved: {size_diff} ({percentage} of original size)")
    logging.info(f"Total elapsed time: {int(hours)} hours, {int(minutes)} minutes, {int(seconds)} seconds")

    release_logger_handlers(logger)

    remove_empty_text_files(log_dir)
    print_dash_across_terminal()

if __name__ == "__main__":
    preset_paths_text_file_path = f"{__file__} - Preset directories.txt"
    
    while True:
        main()
        
