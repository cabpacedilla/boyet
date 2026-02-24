import sys
import asyncio
import random
from playwright.async_api import async_playwright
import urllib.parse

# New helper for human-like pauses
async def random_delay(min_sec=3, max_sec=7):
    delay = random.uniform(min_sec, max_sec)
    await asyncio.sleep(delay)

async def scrape_linkedin(page, query):
    try:
        q = urllib.parse.quote(query)
        url = f"https://www.linkedin.com/jobs/search/?keywords={q}&location=Philippines&f_WT=2&f_JT=C%2CP&f_E=4"
        await page.goto(url, wait_until="load", timeout=30000)
        await random_delay(2, 4) # Pause after load
        
        jobs = []
        cards = await page.query_selector_all("div.base-card")
        for c in cards[:5]:
            title_el = await c.query_selector("h3.base-search-card__title")
            comp_el = await c.query_selector("h4.base-search-card__subtitle")
            link_el = await c.query_selector("a.base-card__full-link")
            if title_el and comp_el and link_el:
                title = (await title_el.inner_text()).strip()
                comp = (await comp_el.inner_text()).strip()
                link = (await link_el.get_attribute("href")).split('?')[0]
                job_id = link.split("-")[-1]
                jobs.append(f"{job_id}|{title}|{comp}|{link}")
        return jobs
    except Exception as e:
        return []

async def scrape_mynimo(page, query):
    try:
        clean_q = query.replace('"', '').replace('(', '').replace(')', '').replace('OR', '').replace('AND', '')
        q = urllib.parse.quote(' '.join(clean_q.split()))
        url = f"https://www.mynimo.com/cebu-jobs/search?q={q}"
        
        await page.goto(url, wait_until="load", timeout=30000)
        await random_delay(2, 5)
        
        jobs = []
        items = await page.query_selector_all("div.job-item")
        for i in items[:5]:
            title_el = await i.query_selector("a.job-title")
            comp_el = await i.query_selector("div.company-name")
            if title_el and comp_el:
                title = (await title_el.inner_text()).strip()
                link = "https://www.mynimo.com" + await title_el.get_attribute("href")
                comp = (await comp_el.inner_text()).strip()
                jobs.append(f"mynimo-{title[:5]}|{title}|{comp}|{link}")
        return jobs
    except Exception as e:
        return []

async def scrape_jobstreet(page, query):
    try:
        clean_q = query.replace('"', '').replace('(', '').replace(')', '').replace('OR', ' ').replace('AND', ' ')
        q = urllib.parse.quote(' '.join(clean_q.split()))
        url = f"https://www.jobstreet.com.ph/en/job-search/{q}-contract-jobs/"
        
        await page.goto(url, wait_until="load", timeout=30000)
        await random_delay(3, 6)
        
        jobs = []
        cards = await page.query_selector_all("article")
        for c in cards[:5]:
            title_el = await c.query_selector("a[data-automation='jobTitle']")
            comp_el = await c.query_selector("a[data-automation='jobCompany']")
            if title_el and comp_el:
                title = (await title_el.inner_text()).strip()
                link = "https://www.jobstreet.com.ph" + await title_el.get_attribute("href")
                comp = (await comp_el.inner_text()).strip()
                jobs.append(f"js-{title[:5]}|{title}|{comp}|{link}")
        return jobs
    except Exception as e:
        return []

async def main():
    query = sys.argv[1] if len(sys.argv) > 1 else "Senior QA"
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        
        results = []
        # Staggered execution
        results.extend(await scrape_linkedin(page, query))
        await random_delay(5, 10) # Pause between portals
        
        results.extend(await scrape_mynimo(page, query))
        await random_delay(5, 10) # Pause between portals
        
        results.extend(await scrape_jobstreet(page, query))
        
        for item in list(set(results)):
            print(item)
            
        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
