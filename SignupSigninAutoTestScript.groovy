/* This test script will signup an account with valid data and signin with the newly created account 
This script was written by Claive Alvin P. Acedilla. Sept. 2020 */

import static com.kms.katalon.core.checkpoint.CheckpointFactory.findCheckpoint
import static com.kms.katalon.core.testcase.TestCaseFactory.findTestCase
import static com.kms.katalon.core.testdata.TestDataFactory.findTestData
import static com.kms.katalon.core.testobject.ObjectRepository.findTestObject
import static com.kms.katalon.core.testobject.ObjectRepository.findWindowsObject
import com.kms.katalon.core.checkpoint.Checkpoint as Checkpoint
import com.kms.katalon.core.cucumber.keyword.CucumberBuiltinKeywords as CucumberKW
import com.kms.katalon.core.mobile.keyword.MobileBuiltInKeywords as Mobile
import com.kms.katalon.core.model.FailureHandling as FailureHandling
import com.kms.katalon.core.testcase.TestCase as TestCase
import com.kms.katalon.core.testdata.TestData as TestData
import com.kms.katalon.core.testobject.TestObject as TestObject
import com.kms.katalon.core.webservice.keyword.WSBuiltInKeywords as WS
import com.kms.katalon.core.webui.keyword.WebUiBuiltInKeywords as WebUI
import com.kms.katalon.core.windows.keyword.WindowsBuiltinKeywords as Windows
import internal.GlobalVariable as GlobalVariable
import org.openqa.selenium.Keys as Keys

// 1. Open a web browser
WebUI.openBrowser('')

// 2. Go to https://develop.signup.com/
WebUI.navigateToUrl('https://develop.signup.com/')

// Verfiy signup.com heading
def URL = WebUI.getUrl()

if (URL == 'https://develop.signup.com') {
    def Heading = WebUI.getText(findTestObject('Object Repository/Page_  - Call Cen_e1945c/h1_Save Over 70                         on _755844'))

    'Verify the value of the element with the value in the specifications with verifyMatch method.'
    WebUI.verifyMatch(Heading, '[text to match]', true, FailureHandling.STOP_ON_FAILURE)

    def HeadingSize = WebUI.getCSSValue(findTestObject('Object Repository/Page_  - Call Cen_e1945c/h1_Save Over 70                         on _755844'), 
        'font-size')

    WebUI.verifyMatch(HeadingSize, '56px', true, FailureHandling.STOP_ON_FAILURE)
}

// 3. Click the Signup button
WebUI.click(findTestObject('Object Repository/Page_  - Call Cen_e1945c/button_Sign up'))

// Fill up the form
// 4. Input company name on the "Company name" text box
WebUI.setText(findTestObject('Object Repository/Page_/input_Company name_company_name'), company)

// 5. Select country in the "Country" list menu
WebUI.selectOptionByValue(findTestObject('Object Repository/Page_/select_Select your country                 _737f91'), 
    country, true)

// 6. Input phone number on the "Phone Number" input box
WebUI.setText(findTestObject('Object Repository/Page_/input_Phone Number_phone_number'), phone)

// 7. Input signatory name on the "Signatory name" text box
WebUI.setText(findTestObject('Object Repository/Page_/input_Signatory name_signatory_name'), name)

// 8. Input email address on the "Email address" input box
WebUI.setText(findTestObject('Object Repository/Page_/input_Email address_email'), email)

// 9. Input password on the "Password" input box
WebUI.setText(findTestObject('Object Repository/Page_/input_Password_password'), password)

// 10. Input confirm password on the "Confirm password" input box
WebUI.setText(findTestObject('Object Repository/Page_/input_Confirm Password_confirmation'), confirm)

// 11. Click the "Create Account" button
WebUI.click(findTestObject('Object Repository/Page_/button_Create Account'))

WebUI.waitForElementVisible(findTestObject('Object Repository/Page_Payment Dues - /img'), 10)

// 12. Click the profile image
WebUI.click(findTestObject('Object Repository/Page_Payment Dues - /img'))

WebUI.waitForElementVisible(findTestObject('Page_Payment Dues - /button_Sign Out'), 10)

// 13. Click the Logout submenu
WebUI.click(findTestObject('Page_Payment Dues - /button_Sign Out'))

WebUI.closeBrowser()

WebUI.openBrowser('')

// 14. Go to https://develop.signin.com/?page=1
WebUI.navigateToUrl('https://develop.signin.com/?page=1')

// Verify signin.com heading
def applyURL = WebUI.getUrl()

if (applyURL == 'https://develop.signin.com/?page=1') {
    def applyHeading = WebUI.getText(findTestObject('Object Repository/Page_Apply - The Easy Way To Get Hired/h1_One video.                             Z_498bc1'))

    'Verify the value of the element with the value in the specifications with verifyMatch method.'
    WebUI.verifyMatch(applyHeading, '[text to match]', true, FailureHandling.STOP_ON_FAILURE)

    def applyHeadingSize = WebUI.getCSSValue(findTestObject('Object Repository/Page_Apply - The Easy Way To Get Hired/h1_One video.                             Z_498bc1'), 
        'font-size')

    WebUI.verifyMatch(applyHeadingSize, '48px', true, FailureHandling.STOP_ON_FAILURE)
}

// 15. Click the "Sign in" button
WebUI.click(findTestObject('Object Repository/Page_Apply - The Easy Way To Get Hired/button_Sign in'))

// 16. Input the email or username on the "Email or username" input box
WebUI.setText(findTestObject('Object Repository/Page_Sign in - /input_Sign In_form-field-0'), email)

// 17. Enter the password on the "Password" input box
WebUI.setText(findTestObject('Object Repository/Page_Sign in - /input_Sign In_form-field-1'), password)

// 18. Click the "Sign in" button
WebUI.sendKeys(findTestObject('Object Repository/Page_Sign in - /input_Sign In_form-field-1'), Keys.chord(Keys.ENTER))

WebUI.waitForElementVisible(findTestObject('Object Repository/Page_Payment Dues - /img'), 10)

// 19. Click the profile image
WebUI.click(findTestObject('Object Repository/Page_Payment Dues - /img'))

WebUI.waitForElementVisible(findTestObject('Page_Payment Dues - /button_Sign Out'), 10)

// 20. Click the Logout submenu
WebUI.click(findTestObject('Object Repository/Page_Payment Dues - /button_Sign Out'))

