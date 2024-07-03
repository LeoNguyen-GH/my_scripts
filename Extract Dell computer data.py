from pathlib import Path
from bs4 import BeautifulSoup
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By
import openpyxl
import csv
import re

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
        data = list(dict.fromkeys(data))
    return data

service_tags = multi_user_input("Input computer service tags to get information from Dell's website (Enter 'q' to continue): ")

downloads_path = Path.home().joinpath("Downloads")

excel_file = downloads_path.joinpath("Dell computer data.xlsx")
excel_file_headers = ["Serial Tag", "Express Service Code", "Warrenty", "Model", "URL", "CPU Model"]

workbook = openpyxl.load_workbook(excel_file) if excel_file.exists() else openpyxl.Workbook()
sheet = workbook.active
if not excel_file.exists():
    sheet.append(excel_file_headers)
    workbook.save(excel_file)

options = webdriver.ChromeOptions()
user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
options.add_argument(f"user-agent={user_agent}")
driver = webdriver.Chrome(options=options)
driver.maximize_window()

# Load URL page
driver.get(r"https://www.dell.com/support/home/en-uk/products")

for tag in service_tags:
    esc, warrenty, model = None, None, None
    print(f"Parsing dell computer with tag '{tag}'")

    # Enter search query into page searchbox
    wait = WebDriverWait(driver, 10)
    input_field = wait.until(EC.element_to_be_clickable((By.ID, 'mh-search-input')))
    input_field.send_keys(tag)

    submit_btn = wait.until(EC.element_to_be_clickable((By.XPATH, '//*[@id="unified-masthead"]/div[1]/div[1]/div[2]/div/button[2]')))
    previous_url = driver.current_url
    while True:
        try:
            current_url = driver.current_url
            if current_url != previous_url:
                break
            submit_btn.click()
            time.sleep(1)
        except Exception:
            pass
    
    soup = BeautifulSoup(driver.page_source, 'html.parser')

    # Get Express Service Code
    esc = soup.find('p', class_='mb-0 d-lg-block d-none').text.lstrip("Express Service Code: ")

    # Get Model
    model = soup.find('h1', class_='h2 mb-0 mb-lg-1 text-center text-lg-left position-relative word-break pt-lg-0 pt-4').text

    # Get Warrenty
    wait.until(EC.presence_of_element_located((By.XPATH, "/html/body/div[5]/div/div[3]/div[1]/div[2]/div[1]/div[2]/div/div/div/div[2]/div[5]/div[1]")))
    warrenty = driver.find_element(By.XPATH, "/html/body/div[5]/div/div[3]/div[1]/div[2]/div[1]/div[2]/div/div/div/div[2]/div[5]/div[1]").text
    for line in warrenty.split('\n'):
        if "Expires" in line:
            warrenty = line.lstrip("Expires ")
            break
        elif "Expired" in line:
            warrenty = line.lstrip("Expired ")
            break
        
    # Click View product specs
    while True:
        try:
            link = wait.until(EC.element_to_be_clickable((By.XPATH, '//*[@id="quicklink-sysconfig"]')))
            link.click()
            break
        except Exception:
            driver.refresh()
    
    # Click the download csv link
    download_link = wait.until(EC.element_to_be_clickable((By.XPATH, '//*[@id="current-config-export"]')))
    download_link.click()

    driver.refresh()
    
    # Parse downloaded csv file
    csv_file_path = downloads_path.joinpath(fr"{tag}.csv")
    
    data = []
    
    with open(csv_file_path, 'r', encoding="utf-8") as csvfile:
        for row in csv.reader(csvfile):
            for item in row:
                regex = re.search(r"(.*)((i|I)\d-\d+.+?)(\s|\,)(.+)", item)
                if regex:
                    data.append(regex.group(2).lower())
    
    # Convert data variable type list to string
    data = ", ".join(data)
    
    data_to_append = [tag, esc, warrenty, model, current_url, data]
    sheet.append(data_to_append)
    workbook.save(excel_file)

    time.sleep(2)