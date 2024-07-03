import time
from datetime import datetime
import os
import logging
from pathlib import Path

def printRed(skk):
    print("\033[91m{}\033[00m".format(skk))
def printGreen(skk):
    print("\033[92m{}\033[00m".format(skk))
def printYellow(skk):
    print("\033[93m{}\033[00m".format(skk))
def printCyan(skk):
    print("\033[96m{}\033[00m".format(skk))

def printRed_Raised(skk):
    return "\033[91m{}\033[00m".format(skk)

def print_dash_across_terminal():
    print("-" * (os.get_terminal_size()).columns)

def multi_user_input(prompt, allow_dupe_input=None):
    print(prompt)

    data = []
    while True:
        user_input = input("").strip()
        if user_input == "q":
            break
        elif not user_input:
            continue
        else:
            data.append(user_input)

    if not allow_dupe_input:
        data = list(dict.fromkeys(data)) # Removes duplicate elements in list
    return data

def check_empty_variable(var):
    if not var:
        printRed("Input is empty")
        return True
    else:
        return False

def multi_user_input_empty_check(prompt, allow_dupe_input=None, convert_int=None):
    while True:
        data = multi_user_input(prompt, allow_dupe_input)
        if check_empty_variable(data) is False:
            if convert_int:
                data = list(map(int, data))
            return data
        
def num_input(prompt, condition, set_message, default_input=None):
    if default_input:
        printCyan(f"{set_message} {default_input}")
        return default_input
    while True:
        try:
            user_input = int(input(prompt))
            if condition(user_input):
                printCyan(f"{set_message} {user_input}")
                return user_input
            raise Exception
        except Exception:
            printRed("Invalid input, try again.")

def countdown_wait(start):
    for i in range(start, -1, -1):
            print(f"Time remaining before continuing: {i} seconds", end='\r')  # Clear the previous line
            time.sleep(1)

def user_choice(prompt, option_selected_Y = None, option_selected_N = None):
    while True:
        user_input = input(prompt).strip().upper()
        if user_input == "Y":
            if option_selected_Y:
                printCyan(option_selected_Y)
            return True
        elif user_input == "N":
            if option_selected_N:
                printCyan(option_selected_N)
            return False
        else:
            printRed("Invalid input, try again")

def directory_contains_files(directory_path):
    for root, dirs, files in Path(directory_path).walk():
        if files:
            print(f"Directory '{directory_path}' is NOT empty")
            return True
    print(f"Directory '{directory_path}' is empty")
    return False

def delete_empty_directory(directory_path):
    print(f"Attemping to delete directory '{directory_path}' if empty")
    for root, dirs, files in os.walk(directory_path, topdown=False):
        for dir_name in dirs:
            dir_path = os.path.join(root, dir_name)
            try:
                os.rmdir(dir_path)
            except OSError:
                print(f"Failed to delete directory (not empty): {dir_path}")
    try:
        os.rmdir(directory_path)
    except OSError:
        print(f"Failed to delete directory (not empty): {directory_path}")

def dir_total_size(dir_path):
    dir_size = 0
    for root, dirs, files in Path(dir_path).walk():
        for file in files:
            dir_size += Path(root, file).stat().st_size
    return dir_size

def bytes_unit_conversion(bytes):
    i = 0
    units = {0: 'B', 1: 'KB', 2: 'MB', 3: 'GB', 4: 'TB',  5: 'PB',  6: 'EB'}
    while bytes > 1024:
        bytes /= 1024
        if i != 6:
            i += 1
    bytes_converted = f"{bytes:.2f} {units[i]}"
    return bytes_converted

# For use with setup_logger function
class CustomFormatter(logging.Formatter):

    grey = "\x1b[38;20m"
    yellow = "\x1b[33;20m"
    red = "\x1b[31;20m"
    bold_red = "\x1b[31;1m"
    reset = "\x1b[0m"
    format = "%(asctime)s - %(levelname)s - %(message)s (%(filename)s:%(lineno)d)"

    FORMATS = {
        logging.DEBUG: grey + format + reset,
        logging.INFO: grey + format + reset,
        logging.WARNING: yellow + format + reset,
        logging.ERROR: red + format + reset,
        logging.CRITICAL: bold_red + format + reset
    }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt, datefmt='%Y-%m-%d, %H:%M:%S')
        return formatter.format(record)

# Uses the CustomFormatter class
# Call logger using: logger = setup_logger(r"log.log", r"error_log.log")
def setup_logger(log_path = None, error_log_path = None, logging_level_console = "NOTSET", logging_level_file = "NOTSET"):
    # create logger
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s (%(filename)s:%(lineno)d)", datefmt="%Y-%m-%d, %H:%M:%S")

    # create console handler with a higher log level
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging_level_console)
    console_handler.setFormatter(CustomFormatter())
    logger.addHandler(console_handler)

    # create file handler which logs even debug messages
    if log_path:
        file_handler_all = logging.FileHandler(log_path, mode='a', encoding='utf-8')
        file_handler_all.setLevel(logging_level_file)
        file_handler_all.setFormatter(formatter)
        logger.addHandler(file_handler_all)

    # create file handler which logs warnings and above
    if error_log_path:
        file_handler_error = logging.FileHandler(error_log_path, mode='a', encoding='utf-8')
        file_handler_error.setLevel(logging.ERROR)
        file_handler_error.setFormatter(formatter)
        logger.addHandler(file_handler_error)

    return logger

def purge_empty_files(dir_path):
    for root, dirs, files in os.walk(dir_path):
        for file in files:
            if file.endswith(('.txt', '.log')):
                file_path = os.path.join(root, file)
                with open(file_path, mode="r", encoding="utf-8") as file:
                    file_contents  = file.read().strip()
                if not file_contents:
                    try:
                        os.remove(file_path)
                    except Exception as e:
                        printRed("Error: {e}")

def get_files_folders(directory):
    file_paths, dir_paths = [], []
    for root, dirs, files in Path(directory).walk():
        file_paths.extend(root.joinpath(file) for file in files if not any(string in file for string in ["Thumbs.db", "desktop.ini"]))
        dir_paths.extend(root.joinpath(dir) for dir in dirs if not any(string in dir for string in ["$RECYCLE.BIN"]))
    return file_paths, dir_paths

# Usage: dt = date_time()
# dt.DMY(), dt.YMD(), dt.HMS()
class date_time:
    # DD-MM-YYYY
    def DMY(self):
        return datetime.now().strftime("%d-%m-%Y")
    # YYYY-MM-DD
    def YMD(self):
        return datetime.now().strftime("%Y-%m-%d")
    # HH.mm.ss
    def HMS(self):
        return datetime.now().strftime("%H.%M.%S")
    
    # HH:mm:ss
    def HMSColon(self):
        return datetime.now().strftime("%H:%M:%S")

# Returns formatted calculated hours, minutes, and seconds
def elapsed_time(seconds):
    hours, remainder = divmod(seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{int(hours):d}h {int(minutes):d}min {int(seconds):d}s"