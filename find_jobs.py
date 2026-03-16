import sys
import asyncio
import random
import urllib.parse
from playwright.async_api import async_playwright

async def random_delay(min_sec=4, max_sec=8):
    await asyncio.sleep(random.uniform(min_sec, max_sec))

async def scrape_portal(page, url, site_id, card_selector, title_sel, comp_sel, link_sel, attr="href"):
    try:
        await page.goto(url, wait_until="load", timeout=40000)
        await random_delay(2, 4)
        
        jobs = []
        cards = await page.query_selector_all(card_selector)
        for c in cards[:12]:
            try:
                t_el = await c.query_selector(title_sel)
                c_el = await c.query_selector(comp_sel)
                l_el = await c.query_selector(link_sel)
                if t_el and c_el and l_el:
                    title = (await t_el.inner_text()).strip()
                    comp = (await c_el.inner_text()).strip()
                    href = await l_el.get_attribute(attr)
                    
                    # Formatting links
                    if site_id == "li": link = href.split('?')[0]
                    elif site_id == "js": link = f"https://www.jobstreet.com.ph{href}".split('?')[0]
                    elif site_id == "in": link = f"https://ph.indeed.com{href}"
                    else: link = f"https://www.mynimo.com{href}" if href.startswith('/') else href
                    
                    # Generate ID
                    jid = f"{site_id}-{hash(link) % 10000000}"
                    jobs.append(f"{jid}|{title}|{comp}|{link}")
            except: continue
        return jobs
    except: return []

async def main():
    query = sys.argv[1] if len(sys.argv) > 1 else "Senior QA"
    q_encoded = urllib.parse.quote(query)
    
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            viewport={'width': 1280, 'height': 800},
            user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        results = []

        # Portal 1: LinkedIn (Remote focus)
        results.extend(await scrape_portal(page, 
            f"https://www.linkedin.com/jobs/search/?keywords={q_encoded}&location=Philippines&f_WT=2", 
            "li", ".base-card", ".base-search-card__title", ".base-search-card__subtitle", "a.base-card__full-link"))
        
        await random_delay(5, 10)

        # Portal 2: Indeed PH
        results.extend(await scrape_portal(page,
            f"https://ph.indeed.com/jobs?q={q_encoded}&l=Philippines",
            "in", ".job_seen_beacon", "h2", "[data-testid='company-name']", "a.jcs-JobTitle"))

        await random_delay(5, 10)

        # Portal 3: JobStreet PH
        # Clean query for JobStreet URL structure
        js_q = query.replace('"', '').replace('(', '').replace(')', '').replace('OR', ' ').replace('AND', ' ')
        js_q_enc = urllib.parse.quote(' '.join(js_q.split()))
        results.extend(await scrape_portal(page,
            f"https://www.jobstreet.com.ph/en/job-search/{js_q_enc}-jobs/",
            "js", "article[data-automation='job-card']", "a[data-automation='jobTitle']", "a[data-automation='jobCompany']", "a[data-automation='jobTitle']"))

        await random_delay(5, 10)

        # Portal 4: Mynimo (Cebu focus)
        my_q = query.replace('"', '').replace('(', '').replace(')', '').replace('OR', '').replace('AND', '')
        my_q_enc = urllib.parse.quote(' '.join(my_q.split()))
        results.extend(await scrape_portal(page,
            f"https://www.mynimo.com/cebu-jobs/search?q={my_q_enc}",
            "my", ".job-item", ".job-title", ".company-name", ".job-title"))

        # Unique filtering
        seen = set()
        for item in results:
            jid = item.split('|')[0]
            if jid not in seen:
                print(item)
                seen.add(jid)

        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
