#!/usr/bin/env python3
import sys
import sqlite3
import os
import hashlib
from transformers import pipeline

# --- CONFIGURATION ---
DB_PATH = os.path.expanduser("~/.cache/science_classifier_cache.db")
# Using a much smarter model for complex taxonomies
MODEL_NAME = "facebook/bart-large-mnli" 
# Lowered for 30+ categories. 0.15 is a strong statistical winner here.
CONFIDENCE_THRESHOLD = 0.15  

CANDIDATE_LABELS = [
    "Physics: Matter, energy, and force",
    "Chemistry: Substances and chemical reactions",
    "Astronomy: Space and celestial bodies",
    "Earth Sciences: Geology, Meteorology, and Oceanography",
    "Biology: Botany, Zoology, and Microbiology",
    "Genetics: Heredity and DNA",
    "Medicine & Health: Diagnosis, treatment, and Pharmacology",
    "Nutrition Science: How food and nutrients affect the body",
    "Sports Science: Physiology, biomechanics, and kinesiology",
    "Electronics Engineering: Design of microchips and Gadgets",
    "Telecommunications: Audio, Video, and Live broadcasting",
    "Computer Engineering: Hardware and software integration",
    "Psychology: Individual mind and behavior",
    "Sociology: Social groups, Culture, and societal structures",
    "Economics & Business: Production, consumption, and markets",
    "Anthropology: Human origins and cultural development",
    "Political Science: Systems of government and global News events",
    "Journalism & Media Studies: News gathering and dissemination",
    "Communication Science: Transmission of messages and Audio/Video",
    "Information Science: Data collection and factual authentication",
    "Mathematics & Statistics: Data analysis for Business and Science",
    "Computer Science: The foundation of modern Technology",
    "Logic: Systematic study of valid inference and reasoning",
    "Arts & Aesthetics: Creative expression, Visual, Performing, and Literary Arts",
    "Tourism & Hospitality: Travel and its impact on economies",
    "History: Chronological study of human events and civilizations"
]

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS cache (text_hash TEXT PRIMARY KEY, label TEXT)")
    conn.commit()
    return conn

def get_cached_label(conn, text):
    text_hash = hashlib.md5(text.encode()).hexdigest()
    cursor = conn.execute("SELECT label FROM cache WHERE text_hash = ?", (text_hash,))
    row = cursor.fetchone()
    return row[0] if row else None

def save_to_cache(conn, text, label):
    text_hash = hashlib.md5(text.encode()).hexdigest()
    conn.execute("INSERT OR REPLACE INTO cache (text_hash, label) VALUES (?, ?)", (text_hash, label))
    conn.commit()

def classify_text(text):
    # Initialize the pipeline with the better model
    classifier = pipeline("zero-shot-classification", model=MODEL_NAME)
    
    # Hypothesis template forces the AI to evaluate the text as a news topic
    result = classifier(
        text, 
        CANDIDATE_LABELS, 
        hypothesis_template="This scientific news report is about {}."
    )
    
    top_label = result['labels'][0]
    top_score = result['scores'][0]

    if top_score >= CONFIDENCE_THRESHOLD:
        return top_label.split(':')[0].strip()
    else:
        return "Science (General)"

if __name__ == "__main__":
    input_text = " ".join(sys.argv[1:]).strip()
    if not input_text:
        sys.exit(0)

    db_conn = init_db()
    cached = get_cached_label(db_conn, input_text)

    if cached:
        print(cached)
    else:
        final_label = classify_text(input_text)
        save_to_cache(db_conn, input_text, final_label)
        print(final_label)
