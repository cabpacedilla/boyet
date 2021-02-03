import static com.kms.katalon.core.testdata.TestDataFactory.findTestData

import com.kms.katalon.core.configuration.RunConfiguration
import com.kms.katalon.core.webui.driver.DriverFactory
import com.kms.katalon.core.webui.keyword.WebUiBuiltInKeywords as WebUI

Date date = new Date()
String todaysDate = date.format('dd-MMMM-yyy HH-mm')

def imgDir = RunConfiguration.getProjectDir() + "screenshots/lionlineAllpagelinks"

def column1 = new Integer[7]
def column2 = new Integer[7]
def column3 = new String[7]
def browser = new String[3]

column1[0] = 1920
column2[0] = 950
column3[0] = "desktop"
column1[1] = 360
column2[1] = 640
column3[1] = "GalaxyS5"
column1[2] = 414
column2[2] = 736
column3[2] = "iPhone8+"
column1[3] = 1440
column2[3] = 770
column3[3] = "laptop"
column1[4] = 375
column2[4] = 812
column3[4] = "iPhoneX"
column1[5] = 1024
column2[5] = 768
column3[5] = "iPad"
column1[6] = 1024
column2[6] = 1366
column3[6] = "iPadPro"

browser[0] = "Chrome"
browser[1] = "Firefox"
browser[2] = "Edge"

def brwsrCtr = 0
def ctr = 0
while ( brwsrCtr <  browser.length )
{
	def column4var
	
	column4var = browser[brwsrCtr]
	
	def browserFolder = "$column4var"
	
	
	
	while ( ctr < column2.length )
	{
		def column1var
		def column2var
		def column3var
		
		column1var = column1[ctr]
		column2var = column2[ctr]
		column3var = column3[ctr]
		
		
		for (def row = 1; row <= findTestData('lionlineAllpagelinks').getRowNumbers() - 1; row++)
		{
			def filename = findTestData('lionlineAllpagelinks').getValue('Name', row)
			def page = findTestData('lionlineAllpagelinks').getValue('page', row)
						
			'Open browser'
			WebUI.openBrowser('')
			
			'Maximize current window'
			WebUI.maximizeWindow()
		
			WebUI.setViewPortSize(column1var, column2var)
			
			'Navigate to Link in row value'			
			WebUI.navigateToUrl(findTestData('lionlineAllpagelinks').getValue('Links', row))	

			def browsername
			
			if(DriverFactory.getExecutedBrowser().getName() == "CHROME_DRIVER") 
			{	
				browsername = "Chrome"
			
			}
			else if(DriverFactory.getExecutedBrowser().getName() == "FIREFOX_DRIVER")
			{	
				browsername = "Firefox"
			}
			else
			{
				browsername = "Edge"
			}
			
			imgDir = RunConfiguration.getProjectDir() + "/screenshots/lionlineAllpagelinks" + "/$browsername" + ' ' + "$todaysDate"
			
			def foldername = "$imgDir" + "/$todaysDate" + "/$column1var" + 'x' + "$column2var" + "$column3var"
			
			'Wait for the page to load'
			WebUI.waitForPageLoad(10)
			
			'Take screenshot and save as png using the filename variables'
			WebUI.takeScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$column1var" + 'x' + "$column2var" + '.png')
			
			WebUI.takeFullPageScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$column1var" + 'x' + "$column2var" + 'Full' + '.png')
			
			'Close web browser'
			WebUI.closeBrowser()
		}
		
		ctr = ctr + 1
	}
	
	brwsrCtr = brwsrCtr + 1
}

