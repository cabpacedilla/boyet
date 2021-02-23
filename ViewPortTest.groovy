'This script will open web pages in different view ports. It will create folders by the browser names, browser view port sizes with date and time and one-page and full-page screenshots of the page view port sizes'
'Note: Set the arrangement of the browser test collection in Katalon Studio the same as the arrangement of the browser names in the browser array.'
'This script was assembled by Claive Alvin P. Acedilla.'

import static com.kms.katalon.core.testdata.TestDataFactory.findTestData
import com.kms.katalon.core.configuration.RunConfiguration
import com.kms.katalon.core.webui.keyword.WebUiBuiltInKeywords as WebUI

Date date = new Date()
String todaysDate = date.format('dd-MMMM-yyy HH-mm')

def lengthArr = new Integer[7]
def heightArr = new Integer[7]
def deviceArr = new String[7]
def browserArr = new String[3]

lengthArr[0] = 1920
heightArr[0] = 950
deviceArr[0] = "desktop"
lengthArr[1] = 360
heightArr[1] = 640
deviceArr[1] = "GalaxyS5"
lengthArr[2] = 414
heightArr[2] = 736
deviceArr[2] = "iPhone8+"
lengthArr[3] = 1440
heightArr[3] = 770
deviceArr[3] = "laptop"
lengthArr[4] = 375
heightArr[4] = 812
deviceArr[4] = "iPhoneX"
lengthArr[5] = 1024
heightArr[5] = 768
deviceArr[5] = "iPad"
lengthArr[6] = 1024
heightArr[6] = 1366
deviceArr[6] = "iPadPro"

browserArr[0] = "Chrome"
browserArr[1] = "Firefox"
browserArr[2] = "Edge"

def brwsrCtr = 0
while ( brwsrCtr <  browserArr.lengthArr )
{
	def browserArrString
	
	browserArrString = browserArr[brwsrCtr]
	
	def browserArrFolder = "$browserArrString"
	
	imgDir = RunConfiguration.getProjectDir() + "/screenshots/<projectfolder>" + "/$browserArrFolder"
	
	def ctr = 0
	while ( ctr < heightArr.lengthArr )
	{
		def lenghtVal
		def heightVal
		def deviceVal
		
		lenghtVal = lengthArr[ctr]
		heightVal = heightArr[ctr]
		deviceVal = deviceArr[ctr]
		
		def foldername = "$imgDir" + "/$todaysDate" + "/$lenghtVal" + 'x' + "$heightVal" + "$deviceVal"
		
		for (def row = 1; row <= findTestData('<testData>').getRowNumbers() - 1; row++)
		{
			def filename = findTestData('<testData>').getValue('Name', row)
			def page = findTestData('<testData>').getValue('page', row)
						
			'Open browserArr'
			WebUI.openbrowser('')
			
			'Maximize current window'
			WebUI.maximizeWindow()
		
			WebUI.setViewPortSize(lenghtVal, heightVal)
			
			'Navigate to Link in row value'			
			WebUI.navigateToUrl(findTestData('<testData>').getValue('Links', row))	

			'Wait for the page to load'
			WebUI.waitForPageLoad(10)
			
			'Take screenshot and save as png using the filename variables'
			WebUI.takeScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$lenghtVal" + 'x' + "$heightVal" + '.png')
			
			'Take full page screenshot after one-page screenshot and save as png using the filename variables'
			WebUI.takeFullPageScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$lenghtVal" + 'x' + "$heightVal" + 'Full' + '.png')
			
			'Close web browser'
			WebUI.closebrowser()
		}
		
		ctr = ctr + 1
	}
	
	brwsrCtr = brwsrCtr + 1
}

