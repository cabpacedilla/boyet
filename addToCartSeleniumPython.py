#!/usr/bin/env python
# Add to cart items
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.common.exceptions import NoSuchElementException  
from selenium.webdriver.common.action_chains import ActionChains  
import unittest  
from selenium.webdriver.support.ui import Select  
from selenium.webdriver.common.keys import Keys
import time  
from selenium.webdriver.support.ui import WebDriverWait  
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.support import expected_conditions as EC  
from selenium.webdriver.chrome.service import Service  
import random  
from selenium.webdriver.chrome.options import Options
import math
from selenium.webdriver.support.select import Select

browser = webdriver.Chrome()

browser.maximize_window()  
browser.get("https://wear.23point5.com/collections/all")  
action = ActionChains(browser)    
fileAddToCart = open("/Users/mini001/Documents/Claive/selenium/addToCartSameAndOtherProducts.txt", "a") 

# Click random product card  
def randProductClick():
    productCards = [element for element in browser.find_elements(By.XPATH, '//div[@class="grid grid--slider grid-1 grid--gap-none"]')]    
    randomProductCard = random.choice(productCards)
    randomProductCard.click()

randProductClick()

qty=[0, 1, 2, 3, 5, 8, 13, 21]

totalPrice = 0.00
totalQty = 0.00

for qtyIndex in range(0, len(qty)):
    productNames = []

    productName = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//h3[@data-product-type="title"]'))).text
    productNames = productNames.append(productName)
    
    def inputQty():
        qtyField = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//input[@name="quantity"]')))
        qtyField.clear()
        qtyField.send_keys(qty[qtyIndex])
        
    inputQty()
   
    def selectSize():
        sizeDropdown = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//div[@data-display="dropdown"]')))
        sizeDropdownMenuItems = [element.text for element in browser.find_elements(By.XPATH, '//select[@class="pf-variant-select"]')]  
        sizeDropdownMenuItems = sizeDropdownMenuItems[0].split("\n            \n                 ")     
        randSizeSelection = random.choice(sizeDropdownMenuItems)
        randSizeSelection = randSizeSelection.strip()
        sizeDropdown.click()
        sizeDropdownMenuItems = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//select[@class="pf-variant-select"]')))
        sizeDropdownMenuItems = Select(sizeDropdownMenuItems)
        sizeDropdownMenuItems.select_by_visible_text(randSizeSelection)

    selectSize()

    def clickAddToCartButton():
        addToCartButton = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//button[@name="add"]')))
        addToCartButton.click()
        time.sleep(8)
    
    clickAddToCartButton()

    def checkCartPaneVisible():
        sideCartPane = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//a[@id="ViewCart"]')))

    def checkCartPaneInvisible():
        sideCartPane = WebDriverWait(browser, 10000).until(EC.invisibility_of_element_located((By.XPATH, '//a[@id="ViewCart"]')))

    checkCartPaneVisible()

    def comparePriceTotal():
        cartProductPrices = [element for element in browser.find_elements(By.XPATH, '//div[@class="cart-item__price"]')]
        productCartPrices = []
        for cartProductPricesIndex in range(0, len(cartProductPrices)):
            productCartPrices.append(float(cartProductPrices[cartProductPricesIndex].find_element(By.TAG_NAME, "strong").text.replace("$", "").replace(",", "")))

        productCartPricesTotal = 0.00
        for productCartPricesIndex in range(0, len(productCartPrices)):
            productCartPricesTotal = productCartPricesTotal + productCartPrices[productCartPricesIndex]
        
        fileAddToCart.write("\n Cart prices total" + str(productCartPricesTotal))

        totalPriceCartElement = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//div[@class="cart__total cart__details--row"]')))
        totalPriceCartText = totalPriceCartElement.find_element(By.TAG_NAME, "strong").text
        totalPriceCartText = totalPriceCartText.replace("$", "")
        totalPriceCartText = totalPriceCartText.replace(",", "")
        totalPriceCart = float(totalPriceCartText)
        fileAddToCart.write("\n Total price cart" + str(totalPriceCart))
        if totalPriceCart == productCartPricesTotal:
            print("Total cart price", totalPriceCart, "is correct.")
            fileAddToCart.write("Total cart price" + str(totalPriceCart) + "is correct.")
        else:
            print("Total cart price", totalPriceCart, "is not correct.")
            fileAddToCart.write("Total cart price" + str(totalPriceCart) + "is not correct.")
    
    def clickRandIncreaseButton():
        increaseButtons = [element for element in browser.find_elements(By.XPATH, '//button[@class="qty-button qty-plus no-js-hidden"]')]
        randIncreaseButton = random.choice(increaseButtons)
        action.move_to_element(randIncreaseButton).click().perform()

    def clickRandDecreaseButton():
        decreaseButtons = [element for element in browser.find_elements(By.XPATH, '//button[@class="qty-button qty-minus no-js-hidden"]')]
        randDereaseButton = random.choice(decreaseButtons)
        action.move_to_element(randDereaseButton).click().perform()
    
    clickRandIncreaseButton()

    time.sleep(5)

    comparePriceTotal()

    def randCartProdNameClick():
        cartProductNames = [element for element in browser.find_elements(By.XPATH, '//a[@class="cart-item__title"]')]
        randCartProductName = random.choice(cartProductNames)
        action.move_to_element(randCartProductName).click().perform()   

    def randCartCardClick():
        cartProductCards = [element for element in browser.find_elements(By.XPATH, '//figure[@class="lazy-image lazy-image--small lazy-image--scale-animation lazyloaded"]')]
        randCarProductCard = random.choice(cartProductCards)
        action.move_to_element(randCarProductCard).click().perform()

    randCartProdNameClick()

    checkCartPaneInvisible()

    time.sleep(5)

    inputQty()

    clickAddToCartButton()
    
    checkCartPaneVisible()
    time.sleep(5)

    comparePriceTotal()
    clickRandDecreaseButton()
    time.sleep(5)
    comparePriceTotal()
    
    randCartCardClick()

    time.sleep(5)

    checkCartPaneInvisible()

    similarItemsCards = [element for element in browser.find_elements(By.XPATH, '//div[@class="grid grid--slider grid-1 grid--gap-none"]')] 
    randSimilarItem = random.choice(similarItemsCards)
    randSimilarItem.click()

    time.sleep(5)

    inputQty()
    selectSize()
    clickAddToCartButton()

    checkCartPaneVisible()
    time.sleep(5)

    comparePriceTotal()
    clickRandIncreaseButton()
    time.sleep(5)
    comparePriceTotal()

    randCartCardClick()

    checkCartPaneInvisible()
    time.sleep(5)
    
    productNavLink = WebDriverWait(browser, 10000).until(EC.visibility_of_element_located((By.XPATH, '//span[text()="Products"]')))
    productNavLink.click()
    
    randProductClick()

browser.close()
    




            
            


