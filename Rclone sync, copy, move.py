from pathlib import Path
import subprocess
from datetime import datetime
import shutil
import re
from common.functions import *

log_path = ""

while True:
    # Set move operation
    options = {
    "1": ["sync", "Sync"],
    "2": ["copyto", "Copyto (Append '(#)' at end of copied files if exist at destination)"], 
    "3": ["moveto", "Moveto (Append '(#)' at end of copied files if exist at destination)"], 
    "4": ["copy", "Copy (Skip all files that exist on destination)"], 
    "5": ["move", "Move (Skip all files that exist on destination)"]
    }
    for key, value in options.items():
        print(key + ". " + value[1])
    while True:
        user_input = input("Enter the numbered option (1, 2, 3 etc.): ")
        if user_input in options:
            move_operation = options[user_input][0]
            break
        printRed("Invalid input, try again")
    printCyan(f"Selected move operation: {move_operation}")

    checksum = None
    if not move_operation in ["copyto", "moveto"]:
        user_input = user_choice("Enabled checksum checks? (Y/N): ", "Checksum checks enabled", "Checksum checks not enabled")
        if user_input is True:
            checksum = "--checksum"

    while True:
        # Set source path
        print("Enter the source directory paths (Enter 'q' to continue):")

        source_paths = []
        while True:
            user_input = input("").strip().replace('"',"")
            if user_input == "q":
                break
            elif not user_input:
                continue
            elif Path(user_input).is_dir():
                source_paths.append(user_input)
            else:
                printRed("Directory path not found, try again")

        source_paths = list(dict.fromkeys(source_paths)) # Removes duplicate elements in list
        if check_empty_variable(source_paths) is True:
            continue
        for source_path in source_paths:
            printCyan(f"Selected source path: {source_path}")

        # Set destination path
        while True:
            destination_path = input("Enter the destination directory path: ").strip().replace('"',"")
            if Path(destination_path).is_dir():
                printCyan(f"Selected destination path: {destination_path}")
                break
            printRed("Directory path not found, try again")
        
        if destination_path in source_paths:
            printRed(f"Source and destination path cannot be the same: {destination_path}")
            continue
        break
    
    input("Press enter to continue move operation")

    # Get the current date and time
    current_datetime = datetime.now()
    formatted_date = current_datetime.strftime('%Y-%m-%d')
    formatted_time = current_datetime.strftime('%H.%M.%S')

    for source_path in source_paths:
        if move_operation in ["copyto", "moveto"]:
            # Iterate over files in the source directory
            for root, dirs, files in Path(source_path).walk():
                for file in files:
                    source_file = Path.joinpath(root, file)

                    # Construct the destination file path
                    relative_path = Path(root).relative_to(source_path)
                    destination_file = Path(destination_path).joinpath(relative_path, file)

                    # Check if the file already exists in the destination
                    counter = 2
                    # Remove leading circle brackets and number inside
                    formatted_filename = re.sub(r'\s*\(\d*\)$', '', Path(file).stem)
                    while Path(destination_file).exists():
                        new_filename = f"{formatted_filename} ({counter})" + Path(file).suffix
                        destination_file = Path(destination_path).joinpath(relative_path, new_filename)
                        counter += 1

                    printCyan(f"{move_operation} '{source_file}' to '{destination_file}'")

                    cmd_args = [
                        "rclone", 
                        move_operation, 
                        source_file, 
                        destination_file, 
                        "--metadata", 
                        "--progress", 
                        "--log-file=" + log_path + f"{move_operation} - Date=" + formatted_date + " & Time=" + formatted_time + ".log", 
                        "--log-level=INFO"
                    ]
                    try:
                        subprocess.run(cmd_args, check=True)
                    except subprocess.CalledProcessError as e:
                        # Check if the error message indicates "directory not found"
                        error_output = str(e.output.decode('utf-8')) if isinstance(e.output, bytes) else str(e)
                        if "returned non-zero exit status" in error_output:
                            printRed(f"Error: {error_output}")

                            if move_operation == "copyto":
                                shutil.copy2(source_file, destination_file)

                                # Check if the file in the destination exists and has the same size as the source file
                                if Path(destination_file).exists() and Path(source_file).stat().st_size == Path(destination_file).stat().st_size:
                                    printGreen(f"File successfully copied and verified in destination.")
                                else:
                                    printRed(f"Error: File copy failed or verification failed in destination.")
                            elif move_operation == "moveto":
                                try:
                                    destination_dir = Path(destination_file).parent
                                    Path(destination_dir).mkdir(parents=True, exist_ok=True)

                                    shutil.move(source_file, destination_file)
                                except Exception as e:
                                    printRed(f"Error: {e}")
                        else:
                            printRed(f"Error '{source_file}': {error_output}")
        else:
            cmd_args = [
                "rclone", 
                move_operation, 
                source_path, 
                destination_path, 
                "--metadata", 
                "--progress", 
                "--check-first", 
                "--create-empty-src-dirs", 
                "--order-by=size,desc", 
                "--transfers=3", 
                "--checkers=20", 
                "--log-file=" + log_path + f"{move_operation} - Date=" + formatted_date + " & Time=" + formatted_time + ".log", 
                "--log-level=INFO"
            ]
            if move_operation != "sync":
                cmd_args.append("--ignore-existing")
            if checksum:
                cmd_args.append(checksum)
            subprocess.run(cmd_args)

    # Get the total seconds elapsed
    end_datetime = datetime.now()
    timeTaken_seconds = (end_datetime - current_datetime).total_seconds()

    # Calculate hours, minutes, and seconds
    hours, remainder = divmod(timeTaken_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    # Format as HH.MM.SS
    printCyan(f"Total elapsed time: {int(hours):d}h {int(minutes):d}min {int(seconds):d}s")
    print_dash_across_terminal()