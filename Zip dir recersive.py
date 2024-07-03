import subprocess
import shutil
from pathlib import Path
from datetime import datetime
import time
from common.functions import *

while True:
    while True:
        user_input = input("Enter the directory path to zip folders: ").strip('"').strip("'")
        
        source_dir = Path(user_input)
        if not source_dir.exists() or not user_input:
            printRed(f"Directory '{user_input}' not found.")
            continue
        else:
            printGreen(f"Directory '{user_input}' found.")

        user_confirmation = user_choice("Confirm directory to continue. (Y/N): ")
        if user_confirmation is True:
            break
        else:
            printYellow("Directory path reset.")

    current_time = datetime.now().strftime("Date=%Y-%m-%d & Time=%H.%M.%S")
    log_file = Path(fr"_Logs\7-Zip\7-Zip log - {current_time}.log")
    logger = setup_logger(log_path = log_file)

    start_time = time.time()
    total_folders = 0
    total_folders_zipped = 0

    for root, dirs, files in Path.walk(source_dir, top_down=False):  
        for file in files:
            file_path = root / file
            file_rel_path = file_path.parent
            zip_filename = Path(str(file_rel_path) + ".cbz")

            # Skip processing files in source_dir
            if file_rel_path != source_dir and file_rel_path.parent != source_dir and not zip_filename.exists():
                total_folders += 1
                logging.info(f"Zipping '{file_rel_path}' -> '{zip_filename}'")
                process = subprocess.run(["7z", "a", "-r", "-mx0", "-tzip", zip_filename, str(file_rel_path)], stdout=subprocess.PIPE)
                output = process.stdout
                
                if Path(file_rel_path).exists() and Path(zip_filename).exists():
                    shutil.rmtree(file_rel_path)
                    total_folders_zipped += 1
                elif not Path(file_rel_path).exists():
                    logging.error(f"{zip_filename} - Failed to create zip file")

                logging.info(f"Current folders zipped: {total_folders_zipped}/{total_folders}.") 
    
    # Calculate total elapsed time
    elapsed_time = time.time() - start_time
    hours, remainder = divmod(elapsed_time, 3600)
    minutes, seconds = divmod(remainder, 60)

    logging.info(f"Processed {total_folders} folders, zipped {total_folders_zipped} subdirectories.")
    logging.info(f"Total elapsed time: {int(hours)} hours, {int(minutes)} minutes, {int(seconds)} seconds.")
