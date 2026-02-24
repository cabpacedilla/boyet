import requests
from bs4 import BeautifulSoup
import urllib.parse
import sys
import re

def fetch_linkedin_jobs(query):
    # Using 4 spaces for indentation consistently
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    }
    
    # Targeting Philippines specifically
    location = "Philippines"
    query_encoded = urllib.parse.quote(query)
    loc_encoded = urllib.parse.quote(location)
    
    url = f"https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords={query_encoded}&location={loc_encoded}&f_E=4&f_WT=2"
    
    try:
        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code != 200:
            return []
    except Exception:
        return []

    soup = BeautifulSoup(response.text, 'html.parser')
    job_cards = soup.find_all(['li', 'div'], class_=lambda x: x and 'job-search-card' in x)
    
    found_jobs = []
    for card in job_cards:
        try:
            link_tag = card.find('a', class_='base-card__full-link')
            if link_tag:
                full_link = link_tag['href'].split('?')[0]
                job_id_match = re.search(r'-(\d+)', full_link)
                job_id = job_id_match.group(1) if job_id_match else full_link
                
                title = card.find('h3', class_='base-search-card__title').text.strip()
                company = card.find('h4', class_='base-search-card__subtitle').text.strip()
                
                found_jobs.append(f"{job_id}|{title}|{company}|{full_link}")
        except:
            continue
            
    return found_jobs

if __name__ == "__main__":
    search_query = sys.argv[1] if len(sys.argv) > 1 else "Senior QA"
    results = fetch_linkedin_jobs(search_query)
    for item in results:
        print(item)
