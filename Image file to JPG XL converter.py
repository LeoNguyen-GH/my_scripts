import concurrent.futures
import subprocess
from pathlib import Path
import time
from collections import Counter
import shutil
import uuid
from datetime import datetime
from common.functions import *

while True:
    while True:
        user_input = input("Enter the directory path to convert image files to .jxl or input a number to automatically set path: ").strip().strip('"')
        
        directory_path = Path(user_input)

        if not directory_path.exists() or not user_input:
            printRed(f"The directory '{directory_path}' does not exist. Please enter a valid path.")
            continue
        printGreen(f"The directory '{directory_path}' has been validated.")

        user_confirmation = user_choice("Is this the correct directory to convert images to JXL? (Y/N): ")
        if user_confirmation is True:
            break
        printYellow("Input reset")

    # Max number of images to process at the same time
    while True:
        max_workers = input("Input the number of max workers (Recommended number, # of CPU cores): ")
        if max_workers.isdigit() and int(max_workers) > 0:
            max_workers = int(max_workers)
            break
        printRed(f"Invalid input, try again")

    # Calculate directory folder size
    original_dir_size = dir_total_size(directory_path)
    
    # Set up logging
    log_file_current_date_time = datetime.now().strftime("Date=%Y-%m-%d & Time=%H.%M.%S")
    log_dir = r"_Logs\Image to JXL converter"
    logger = setup_logger(
        log_path = fr"{log_dir}\{log_file_current_date_time}.log", 
        error_log_path = fr"{log_dir}\{log_file_current_date_time} - error log.log",
        logging_level_console = "INFO"
    )
    logging.getLogger('asyncio').disabled = True
    # Temp directory name
    temporary_dir_path = directory_path.joinpath("#Temp")

    def process_image(file):
        input_file = file
        unique_id = str(uuid.uuid4())
        source_file = temporary_dir_path.joinpath(file.stem + "_" + unique_id + file.suffix)
        processed_file = source_file.with_suffix('.jxl')

        source_file.parent.mkdir(parents=True, exist_ok=True)
        processed_file.parent.mkdir(parents=True, exist_ok=True)

        # Log the original and temporary file names
        logging.debug(f"'{input_file}' - Original File Name to '{source_file}' - Temporary File Name")

        # Move the image to the temporary directory
        file.rename(source_file)

        def reverse_process(original_file_path, file_path, remove_file, logs, extra_remove_file = None):
            # Preserve the original file if error occured
            logging.error(logs)
            file_path.rename(original_file_path)
            printYellow(f"Moving back '{original_file_path}' to original location")
            # Removes cjxl processed processed_file file
            if remove_file.exists():
                remove_file.unlink()
            if extra_remove_file and extra_remove_file.exists():
                extra_remove_file.unlink()

        try:
            subprocess.run(["cjxl", str(source_file), "--distance", "0", "--effort", "10", str(processed_file)], stderr=subprocess.PIPE, check=True)
        except (subprocess.CalledProcessError, Exception) as e:
            reverse_process(input_file, source_file, processed_file, f"{input_file} - Error: {e}")
            return
        finally:
            if not processed_file.exists():
                reverse_process(input_file, source_file, processed_file, f"{input_file} - Procesed file not found")
                return

        # decode the processed file
        decoded_processed_file = source_file.with_stem(source_file.stem + "_decoded")
        subprocess.run(["djxl", str(processed_file), str(decoded_processed_file)], stderr=subprocess.PIPE, check=True)

        # Compare decoded processed file and source file 
        compare_cmd = ['magick', 'compare', '-metric', 'ae', str(source_file), str(decoded_processed_file), 'NUL']
        compared_result = subprocess.run(compare_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Move processed file back to source file directory if result returncode is 0
        if compared_result.returncode == 0:
            logging.info(f"'{input_file}' - Done: magick compare returned {compared_result.returncode}")
            processed_file.rename(input_file.with_suffix('.jxl'))
            # Removes the original image file and decoded processed file
            decoded_processed_file.unlink()
            source_file.unlink()

            total_counter['processed'] += 1
            print(f"Current images processed: {total_counter['processed']}/{total_counter['submitted']}")
        else:
            reverse_process(input_file, source_file, processed_file, f"{input_file} - Failed: magick compare returned {compared_result.returncode}", decoded_processed_file)

    def filename_validation(filename):
        try:
            filename.encode('ascii')
        except UnicodeEncodeError:
            logging.warning(f"{file} - Skipped (contains non-ASCII characters)")
            return False
        else:
            return True
        
    start_time = time.time()

    total_counter = Counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        for file in directory_path.glob('**/*'):
            if  file.is_file() and file.suffix.lower() in ('.png', '.jpg', '.jpeg') and filename_validation(file.name) is True:
                total_counter['submitted'] += 1
                executor.submit(process_image, file)

    # Remove the temporary directory if it exists
    if temporary_dir_path.exists():
        shutil.rmtree(temporary_dir_path)

    elapsed_time = time.time() - start_time
    hours, remainder = divmod(elapsed_time, 3600)
    minutes, seconds = divmod(remainder, 60)

    # Calculate directory size after processing
    processed_dir_size = dir_total_size(directory_path)
    # Calculate size difference between original and processed directory
    size_diff = bytes_unit_conversion(original_dir_size - processed_dir_size)
    # Calculate the difference between original and process directory in percentage terms
    percentage_processed_to_original = (processed_dir_size / original_dir_size) * 100
    percentage_processed_to_original = f"{percentage_processed_to_original:.3f}%"

    logging.info(f"Total images submitted: {total_counter['submitted']}, processed: {total_counter['processed']}")
    logging.info(f"Total space saved: {size_diff} ({percentage_processed_to_original} of original size)")
    logging.info(f"Total elapsed time: {int(hours)} hours, {int(minutes)} minutes, {int(seconds)} seconds")

    # close logging handler
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()

    purge_empty_files(log_dir)
    print_dash_across_terminal()