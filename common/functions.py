import time
from datetime import datetime
import os
import logging
from pathlib import Path
import openpyxl

def print_colored(text: str, color: str = "white", no_newline: bool = False, end_line: str = "\n"):
    color_codes = {
        "black": "30",
        "red": "31",
        "green": "32",
        "yellow": "33",
        "blue": "34",
        "magenta": "35",
        "cyan": "36",
        "white": "37",
        "bright black": "90",
        "bright red": "91",
        "bright green": "92",
        "bright yellow": "93",
        "bright blue": "94",
        "bright magenta": "95",
        "bright cyan": "96",
        "bright white": "97"
    }
    
    if color not in color_codes:
        raise ValueError(f"Invalid color '{color}'. Valid options are: {', '.join(color_codes.keys())}")
    
    end_line = "" if no_newline else end_line
    print(f"\033[{color_codes[color]}m{text}\033[00m", end=end_line)

def print_dash_across_terminal():
    print("-" * (os.get_terminal_size()).columns)

def multi_user_input(prompt: str, dupe_input: bool = False, convert_to_int: bool = False):
    print(prompt)
    
    data = []
    while not data:
        while True:
            user_input = input("").strip()
            if user_input == "q":
                break
            elif not user_input:
                continue
            else:
                data.append(user_input)
    
    if not dupe_input:
        data = list(dict.fromkeys(data))
    if convert_to_int:
        data = list(map(int, data))
    return data
        
def valid_num_input(prompt: str, condition: callable, cond_met_msg: str = None):
    while True:
        try:
            user_input = int(input(prompt))
            
            if condition(user_input):
                if cond_met_msg:
                    print_colored(cond_met_msg.format(user_input=user_input), "cyan")
                return user_input
            raise ValueError
        except ValueError:
            print_colored("Invalid input.", "red")

def countdown_wait(start):
    for i in range(start, -1, -1):
            print(f"Time remaining before continuing: {i} seconds", end='\r')  # Clear the previous line
            time.sleep(1)

def get_user_confirmation(prompt: str, option_selected_Y: str = None, option_selected_N: str = None):
    while True:
        user_input = input(prompt).strip().upper()
        
        if user_input == "Y":
            if option_selected_Y:
                print_colored(option_selected_Y, "cyan")
            return True
        elif user_input == "N":
            if option_selected_N:
                print_colored(option_selected_N, "cyan")
            return False
        else:
            print_colored("Invalid input.", "red")

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
    format = "%(asctime)s - %(levelname)s - %(message)s" #"%(asctime)s - %(levelname)s - %(message)s (%(filename)s:%(lineno)d)"

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
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s", datefmt="%Y-%m-%d, %H:%M:%S") #logging.Formatter("%(asctime)s - %(levelname)s - %(message)s (%(filename)s:%(lineno)d)", datefmt="%Y-%m-%d, %H:%M:%S")

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

def remove_empty_text_files(dir_path):
    file_paths, _ = get_files_and_folders(dir_path)
    
    def read_and_delete(file_path):
        with open(file_path, mode="r", encoding="utf-8") as file:
            file_contents  = file.read().strip()
            
        if not file_contents:
            file_path.unlink(missing_ok=True)
    
    for file_path in file_paths:
        if file_path.suffix in ('.txt', '.log'):
            read_and_delete(file_path)

def get_files_and_folders(dir_path):
    file_paths, dir_paths = [], []
    for root, dirs, files in Path(dir_path).walk():
        dirs[:] = [dir for dir in dirs if dir not in ["$RECYCLE.BIN"]]
        
        file_paths.extend(root / file for file in files if not any(string in file for string in ["Thumbs.db", "desktop.ini"]))
        dir_paths.extend(root / dir for dir in dirs)
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

def create_text_file(text_file_path):
    try:
        with open(text_file_path, mode="x") as file:
            file.write("")
    except FileExistsError:
        pass

def initalize_excel_file(excel_file_path, excel_file_headers: list):
    excel_file_path = Path(excel_file_path)
    workbook = openpyxl.load_workbook(excel_file_path) if excel_file_path.exists() else openpyxl.Workbook()
    sheet = workbook.active
    
    if not excel_file_path.exists():
        sheet.append(excel_file_headers)
        workbook.save(excel_file_path)
        
    return workbook, sheet
