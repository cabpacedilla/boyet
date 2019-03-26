//This script will verify if the value of the element(s) for assertions is/are equal to the value(s) in the specification.
//This script was assembled by Claive Alvin P. Acedilla 

import static com.kms.katalon.core.checkpoint.CheckpointFactory.findCheckpoint
import static com.kms.katalon.core.testcase.TestCaseFactory.findTestCase
import static com.kms.katalon.core.testdata.TestDataFactory.findTestData
import static com.kms.katalon.core.testobject.ObjectRepository.findTestObject
import com.kms.katalon.core.checkpoint.Checkpoint as Checkpoint
import com.kms.katalon.core.cucumber.keyword.CucumberBuiltinKeywords as CucumberKW
import com.kms.katalon.core.mobile.keyword.MobileBuiltInKeywords as Mobile
import com.kms.katalon.core.model.FailureHandling as FailureHandling
import com.kms.katalon.core.testcase.TestCase as TestCase
import com.kms.katalon.core.testdata.TestData as TestData
import com.kms.katalon.core.testobject.TestObject as TestObject
import com.kms.katalon.core.webservice.keyword.WSBuiltInKeywords as WS
import com.kms.katalon.core.webui.keyword.WebUiBuiltInKeywords as WebUI
import internal.GlobalVariable as GlobalVariable
import org.openqa.selenium.Keys as Keys
import com.kms.katalon.core.webui.driver.DriverFactory as DF
'Import driverfactory to get name of test browser'

 'Loop data in Excel by row'
for (def row = 1; row <= findTestData('Name of test data').getRowNumbers(); row++) {

'Open browser'
WebUI.openBrowser('')

'Navigate to URL in row value'
WebUI.navigateToUrl(findTestData('Name of test data').getValue('URL data row header', row))

'Define variables for the screenshot filename'
def filename = findTestData('Name of test data').getValue('file name data row header', row)
 
'Get browsername by variable for name of test browser'
def browsername = DF.getWebDriver().getCapabilities().getBrowserName()
 
'Define variable for data verification for assertion'
def currentURL = findTestData('Name of test data').getValue('URL data row header', row)

'Assert page element object of URL with verifyMatch to variable'
if (currentURL == 'specific URL') {
def marketpracticetext = WebUI.getText(findTestObject('element path in Object Repository'))
 
WebUI.verifyMatch(marketpracticetext, 'specific text for text assertion, true, FailureHandling.STOP_ON_FAILURE)
}

'…More page elements assertions here using the if condition and verifyMatch verifications…'

'Maximize window'
WebUI.maximizeWindow()
 
'Zoom page to 30% to view entire page including long pages'
WebUI.executeJavaScript('document.body.style.zoom=\'30%\'', null)
 
'Wait for the page to load'
WebUI.waitForPageLoad(5)
 
'Take screenshot and save as png using the filename variables'
WebUI.takeScreenshot(("$filename" + " $browsername") + '.png')
 
'Close web browser'
WebUI.closeBrowser()
}

