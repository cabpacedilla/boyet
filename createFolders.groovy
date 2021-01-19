import static com.kms.katalon.core.testdata.TestDataFactory.findTestData
import com.kms.katalon.core.configuration.RunConfiguration
import com.kms.katalon.core.webui.keyword.WebUiBuiltInKeywords as WebUI

Date date = new Date()
String todaysDate = date.format('dd-MMMM-yyy HH-mm')

def imgDir = RunConfiguration.getProjectDir() + "screenshots/<testData>"

def length = new Integer[7]
def width = new Integer[7]
def device = new String[7]
def browser = new String[3]

length[0] = 1920
width[0] = 950
device[0] = "desktop"
length[1] = 360
width[1] = 640
device[1] = "GalaxyS5"
length[2] = 414
width[2] = 736
device[2] = "iPhone8+"
length[3] = 1440
width[3] = 770
device[3] = "laptop"
length[4] = 375
width[4] = 812
device[4] = "iPhoneX"
length[5] = 1024
width[5] = 768
device[5] = "iPad"
length[6] = 1024
width[6] = 1366
device[6] = "iPadPro"

browser[0] = "Chrome"
browser[1] = "Firefox"
browser[2] = "Edge"

def brwsrCtr = 0
while ( brwsrCtr <  browser.length )
{
	def browserString
	
	browserString = browser[brwsrCtr]
	
	def browserFolder = "$browserString"
	
	imgDir = RunConfiguration.getProjectDir() + "/screenshots/<projectfolder>" + "/$browserFolder"
	
	def ctr = 0
	while ( ctr < width.length )
	{
		def lengthString
		def widthString
		def deviceString
		
		lengthString = length[ctr]
		widthString = width[ctr]
		deviceString = device[ctr]
		
		def foldername = "$imgDir" + "/$todaysDate" + "/$lengthString" + 'x' + "$widthString" + "$deviceString"
		
		for (def row = 1; row <= findTestData('<testData>').getRowNumbers() - 1; row++)
		{
			def filename = findTestData('<testData>').getValue('Name', row)
			def page = findTestData('<testData>').getValue('page', row)
						
			'Open browser'
			WebUI.openBrowser('')
			
			'Maximize current window'
			WebUI.maximizeWindow()
		
			WebUI.setViewPortSize(lengthString, widthString)
			
			'Navigate to Link in row value'			
			WebUI.navigateToUrl(findTestData('<testData>').getValue('Links', row))	

			'Wait for the page to load'
			WebUI.waitForPageLoad(10)
			
			'Take screenshot and save as png using the filename variables'
			WebUI.takeScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$lengthString" + 'x' + "$widthString" + '.png')
			
			WebUI.takeFullPageScreenshot(("$foldername/$filename") + ' ' + "$page" + ' ' + 'page' + ' ' + "$lengthString" + 'x' + "$widthString" + 'Full' + '.png')
			
			'Close web browser'
			WebUI.closeBrowser()
		}
		
		ctr = ctr + 1
	}
	
	brwsrCtr = brwsrCtr + 1
}

