
/* This Selenium test script will navigate, verify and populate data for the "Successful purchase of items" user flow.
This script was written by Claive Alvin P. Acedilla. 2019 
Note: The test object, page objects and data object should be saved in separate files */

/* SuccesfulPurchaseOfItems.java tests script */

package com.seleniumframework.tests;

import org.testng.annotations.Test;
import com.seleniumframework.core.Browser;
import com.seleniumframework.core.Log;
import com.seleniumframework.dataobjects.TestData;
import com.seleniumframework.pageobjects.siteHome;
import com.seleniumframework.pageobjects.AutomobileInsurancePage;

// Inherit Browser.java class
public class SuccesfulPurchaseOfItems extends Browser 
{
	@Test
	public void SuccessfulPurchaseOfItems() throws Exception 
	{
		Log.setStoryName("Purchase Vehicle");
		
		// 1. Navigate to URL using Browser class driver
		getDriver().get(TestData.Urls.siteUrl());
		
		// Run Test scripts by calling base page element methods and TestData base test values
		
      		// 2. Verify vehicle navigation links 
		siteHome.navSection.verifyAutomobileNavLink();
		siteHome.navSection.verifyTruckNavLink();
		siteHome.navSection.verifyMotorcycleNavLink();
		siteHome.navSection.verifyCamperNavLink();
		
		// 3. Click the Automobile hyperlink
		siteHome.navSection.clickAutomobileNavLink();
		
		// 4. Verify Automobile Insurance nav links
		AutomobileInsurancePage.navSection.vrfyAutoInsuranceLbl();
		AutomobileInsurancePage.navSection.vrfyVehicleDataNavLink();
		AutomobileInsurancePage.navSection.vrfyInsurantDataNavLink();
		AutomobileInsurancePage.navSection.vrfyProductDataNavLink();
		AutomobileInsurancePage.navSection.vrfyPriceOptionNavLink();
		AutomobileInsurancePage.navSection.vrfySendQuoteNavLink();
		
		// 5. Populate Vehicle Data fields
		AutomobileInsurancePage.vehicleDataSection.selMake(TestData.PurchaseInfo.VehicleDataInfo.Make());
		AutomobileInsurancePage.vehicleDataSection.setEnginePerformance(TestData.PurchaseInfo.VehicleDataInfo.EnginePerformance());
		AutomobileInsurancePage.vehicleDataSection.setDateOfManufacture(TestData.PurchaseInfo.VehicleDataInfo.ManufactureDate());
		AutomobileInsurancePage.vehicleDataSection.selNumOfSeats(TestData.PurchaseInfo.VehicleDataInfo.SeatNumbers());
		AutomobileInsurancePage.vehicleDataSection.selFuelType(TestData.PurchaseInfo.VehicleDataInfo.FuelType());
		AutomobileInsurancePage.vehicleDataSection.setListPrice(TestData.PurchaseInfo.VehicleDataInfo.ListPrice());
		AutomobileInsurancePage.vehicleDataSection.setLicensePlateNumber(TestData.PurchaseInfo.VehicleDataInfo.LicensePlateNumber());
		AutomobileInsurancePage.vehicleDataSection.setAnnualMileage(TestData.PurchaseInfo.VehicleDataInfo.AnnualMileage());
		
		// 6. Click Next button
		AutomobileInsurancePage.vehicleDataSection.clickNext();

		// 7. Populate Insurant Data fields
		AutomobileInsurancePage.insurantDataSection.setFirstName(TestData.PurchaseInfo.InsurantDataInfo.FirstName());
		AutomobileInsurancePage.insurantDataSection.setLastName(TestData.PurchaseInfo.InsurantDataInfo.LastName());
		AutomobileInsurancePage.insurantDataSection.setDateOfBirth(TestData.PurchaseInfo.InsurantDataInfo.DateOfBirth());
		AutomobileInsurancePage.insurantDataSection.selGender();
		AutomobileInsurancePage.insurantDataSection.setStreetAddress(TestData.PurchaseInfo.InsurantDataInfo.StreetAddress());
		AutomobileInsurancePage.insurantDataSection.selCountry(TestData.PurchaseInfo.InsurantDataInfo.Country());
		AutomobileInsurancePage.insurantDataSection.setZipCode(TestData.PurchaseInfo.InsurantDataInfo.ZipCode());
		AutomobileInsurancePage.insurantDataSection.setCity(TestData.PurchaseInfo.InsurantDataInfo.City());
		AutomobileInsurancePage.insurantDataSection.selOccupation(TestData.PurchaseInfo.InsurantDataInfo.Occupation());
		AutomobileInsurancePage.insurantDataSection.selHobbySpeeding();
		AutomobileInsurancePage.insurantDataSection.selHobbySkydiving();

		// 8. Click Next button
		AutomobileInsurancePage.insurantDataSection.clickNextProductBtn();
		
		// 9. Populate Product Data Fields
		AutomobileInsurancePage.productDataSection.setStartDate(TestData.PurchaseInfo.ProductDataInfo.StartDate());
		AutomobileInsurancePage.productDataSection.selInsuranceSum(TestData.PurchaseInfo.ProductDataInfo.InsuranceSum());
		AutomobileInsurancePage.productDataSection.selMeritRating(TestData.PurchaseInfo.ProductDataInfo.MeritRating());
		AutomobileInsurancePage.productDataSection.selDamageInsurance(TestData.PurchaseInfo.ProductDataInfo.DamageInsurance());
		AutomobileInsurancePage.productDataSection.selOptionalProducts();
		AutomobileInsurancePage.productDataSection.selCourtesyCar(TestData.PurchaseInfo.ProductDataInfo.CourtesyCar());
		
		// 10. Click Next button
		AutomobileInsurancePage.productDataSection.clickNextPriceBtn();
		
		// 11. Select Ultimate Price radio
		AutomobileInsurancePage.priceSection.selUltimate();
		
		// 12. Click Next button
		AutomobileInsurancePage.priceSection.clickNextQuoteBtn();
				
		
		// 13. Populate Send Quote data fields
		AutomobileInsurancePage.sendQuoteSection.setEmail(TestData.PurchaseInfo.SendQuoteInfo.Email());
		AutomobileInsurancePage.sendQuoteSection.setUsername(TestData.PurchaseInfo.SendQuoteInfo.Username());
		AutomobileInsurancePage.sendQuoteSection.setPassword(TestData.PurchaseInfo.SendQuoteInfo.Password());
		AutomobileInsurancePage.sendQuoteSection.setConfirmPassword(TestData.PurchaseInfo.SendQuoteInfo.ConfirmPassword());
		
		// 14. Click Send button
		AutomobileInsurancePage.sendQuoteSection.clickSendBtn();
		
		// 15. Verify send email success
		AutomobileInsurancePage.emailSuccess.vrfyEmailSuccessLbl();
		
		// 16. Click Yes button
		AutomobileInsurancePage.emailSuccess.clickYes();
    
	}	
}


/* siteHome.java pageobject */

package com.seleniumframework.pageobjects;

import org.openqa.selenium.By;

// Inherit element classes
import com.seleniumframework.webelements.Button;
import com.seleniumframework.webelements.Element;
import com.seleniumframework.webelements.Link;
import com.seleniumframework.webelements.TextBox;

public class siteHome {
	
	public static class navSection 
	{
		private static Link _linkAutomobile = new Link("Automobile", By.id("nav_automobile"));
		private static Link _linkTruck = new Link("Truck", By.id("nav_truck"));
		private static Link _linkMotorcycle= new Link("Motorcycle", By.id("nav_motorcycle"));
		private static Link _linkCamper= new Link("Camper", By.id("nav_camper"));
		
		// Verify vehicle nav links
		public static void verifyAutomobileNavLink() 
		{
			_linkAutomobile.verifyDisplayed();
		}		
		
		public static void verifyTruckNavLink() 
		{
			_linkTruck.verifyDisplayed();
		}
		
		public static void verifyMotorcycleNavLink() 
		{
			_linkMotorcycle.verifyDisplayed();
		}
		
		public static void verifyCamperNavLink() 
		{
			_linkCamper.verifyDisplayed();
		}
		
		// Click Automobile nav link
		public static void clickAutomobileNavLink() 
		{
			_linkAutomobile.click();
		}			
	}
}

/* AutomobileInsurancePage.java pageobject */

package com.seleniumframework.pageobjects;

import org.openqa.selenium.By;

// Inherit element classes
import com.seleniumframework.webelements.Button;
import com.seleniumframework.webelements.CheckBox;
import com.seleniumframework.webelements.Element;
import com.seleniumframework.webelements.Link;
import com.seleniumframework.webelements.ListBox;
import com.seleniumframework.webelements.RadioButton;
import com.seleniumframework.webelements.TextBox;

public class AutomobileInsurancePage {
	
	public static class navSection 
	{
		// Locate elements
		private static Element _lblAutoInsurance = new Element("Automobile Insurance", By.id("selectedinsurance"));
		private static Link _linkEnterVehicleData = new Link("Enter Vehicle Data", By.id("entervehicledata"));
		private static Link _linkEnterInsurantData = new Link("Enter Insurant Data", By.id("enterinsurantdata"));
		private static Link _linkEnterProductData = new Link("Enter Product Data", By.id("enterproductdata"));
		private static Link _linkSelectPriceOption = new Link("Select Price Option", By.id("selectpriceoption"));
		private static Link _linkSendQuote = new Link("Send Quote", By.id("sendquote"));
		
		
		// Verify Automobile Insurance nav links with element method
		public static void vrfyAutoInsuranceLbl() 
		{
			_lblAutoInsurance.verifyDisplayed();
		}	
		
		public static void vrfyVehicleDataNavLink() 
		{
			_linkEnterVehicleData.verifyDisplayed();
		}
		
		public static void vrfyInsurantDataNavLink() 
		{
			_linkEnterInsurantData.verifyDisplayed();
		}	
		
		public static void vrfyProductDataNavLink() 
		{
			_linkEnterProductData.verifyDisplayed();
		}
		
		public static void vrfyPriceOptionNavLink() 
		{
			_linkSelectPriceOption.verifyDisplayed();
		}	
		
		public static void vrfySendQuoteNavLink() 
		{
			_linkSendQuote.verifyDisplayed();
		}
		
	}
	
	public static class vehicleDataSection
	{
		// Locate elements
		private static ListBox _lstBoxMake = new ListBox("Make", By.xpath("//select[@id='make']"));
		private static TextBox _txtBoxEnginePerformance = new TextBox("Engine Performance", By.xpath("//input[@id='engineperformance']"));
		private static TextBox _txtBoxDateOfManufacture = new TextBox("Date of Manufacture", By.xpath("//input[@id='dateofmanufacture']"));
		private static ListBox _lstSeatNums = new ListBox("Number of Seats", By.xpath("//select[@id='numberofseats']"));
		private static ListBox _lstFuelType = new ListBox("Fuel Type", By.xpath("//select[@id='fuel']"));
		private static TextBox _txtBoxListPrice = new TextBox("List Price", By.xpath("//input[@id='listprice']"));
		private static TextBox _txtBoxLicensePlateNumber = new TextBox("Licencse Plate Number", By.xpath("//input[@id='licenseplatenumber']"));
		private static TextBox _txtBoxAnnualMileage = new TextBox("Annual Mileage", By.xpath("//input[@id='annualmileage']"));
		private static Button _btnNext = new Button("Next", By.xpath("//button[@id='nextenterinsurantdata']"));
		
		// Process data with the elements using a method of the elements
		public static void selMake(String make) 
		{
			_lstBoxMake.selectByVisibleText(make);
		}
		
		public static void setEnginePerformance(String engineperf) 
		{
			_txtBoxEnginePerformance.setText(engineperf);
		}
		
		public static void setDateOfManufacture(String manufacturedate) 
		{
			_txtBoxDateOfManufacture.setText(manufacturedate);
		}
		
		public static void selNumOfSeats(String seatnums) 
		{
			_lstSeatNums.selectByVisibleText(seatnums);
		}
		
		public static void selFuelType(String fueltype) 
		{
			_lstFuelType.selectByVisibleText(fueltype);
		}
		
		public static void setListPrice(String listprice) 
		{
			_txtBoxListPrice.setText(listprice);
		}
		
		public static void setLicensePlateNumber(String licenseplate) 
		{
			_txtBoxLicensePlateNumber.setText(licenseplate);
		}
		
		public static void setAnnualMileage(String annualmileage) 
		{
			_txtBoxAnnualMileage.setText(annualmileage);
		}
		
		public static void clickNext() 
		{
			_btnNext.click();
		}
	}

	public static class insurantDataSection
	{
		// Locate elements
		private static TextBox _txtBoxFirstName = new TextBox("First Name", By.xpath("//input[@id='firstname']"));
		private static TextBox _txtBoxLastName = new TextBox("Last Name", By.xpath("//input[@id='lastname']"));
		private static TextBox _txtBoxDateOfBirth = new TextBox("Date of Birth", By.xpath("//input[@id='birthdate']"));
		private static RadioButton _rdoGender = new RadioButton("Gender", By.xpath("(//label[@class=\"ideal-radiocheck-label\"])[1]"));
		private static TextBox _txtBoxStreetAddress = new TextBox("Street Address", By.xpath("//input[@id='streetaddress']"));
		private static ListBox _lstCountry = new ListBox("Country", By.xpath("//select[@id='country']"));
		private static TextBox _txtBoxZipCode = new TextBox("Zip Code", By.xpath("//input[@id='zipcode']"));
		private static TextBox _txtBoxCity = new TextBox("City", By.xpath("//input[@id='city']"));
		private static ListBox _lstOccupation = new ListBox("Occupation", By.xpath("//select[@id='occupation']"));
		private static CheckBox _chkHobbySpeeding = new CheckBox("Hobbies", By.xpath("(//span[@class=\"ideal-check\"])[1]"));
		private static CheckBox _chkHobbySkydiving = new CheckBox("Hobbies", By.xpath("(//span[@class=\"ideal-check\"])[3]"));
		private static Button _btnNextProduct = new Button("Next", By.xpath("//button[@id='nextenterproductdata']"));
		
		// Process data with the elements using a method of the elements
		public static void setFirstName(String firstname) 
		{
			_txtBoxFirstName.setText(firstname);
		}
		
		public static void setLastName(String lastname) 
		{
			_txtBoxLastName.setText(lastname);
		}
		
		public static void setDateOfBirth(String dob) 
		{
			_txtBoxDateOfBirth.setText(dob);
		}
		
		public static void selGender() 
		{
			_rdoGender.click();
		}
		
		public static void setStreetAddress(String streetaddress) 
		{
			_txtBoxStreetAddress.setText(streetaddress);
		}
		
		public static void selCountry(String country) 
		{
			_lstCountry.selectByVisibleText(country);
		}
		
		public static void setZipCode(String zipcode) 
		{
			_txtBoxZipCode.setText(zipcode);
		}
		
		public static void setCity(String city) 
		{
			_txtBoxCity.setText(city);
		}
		
		public static void selOccupation(String occupation) 
		{
			_lstOccupation.selectByVisibleText(occupation);
		}
		
		public static void selHobbySpeeding() 
		{
			_chkHobbySpeeding.click();
		}
		
		public static void selHobbySkydiving() 
		{
			_chkHobbySkydiving.click();
		}
				
		public static void clickNextProductBtn() 
		{
			_btnNextProduct.click();
		}
	}
	

	public static class productDataSection
	{
		// Locate elements
		private static TextBox _txtBoxStartDate = new TextBox("Start Date", By.xpath("//input[@id='startdate']"));
		private static ListBox _lstInsuranceSum = new ListBox("Insurance Sum", By.xpath("//select[@id='insurancesum']"));
		private static ListBox _lstMeritRating = new ListBox("Merit Rating", By.xpath("//select[@id='meritrating']"));
		private static ListBox _lstDamageInsurance = new ListBox("Damage Insurance", By.xpath("//select[@id='damageinsurance']"));
		private static CheckBox _chkOptionalProducts = new CheckBox("Optional Products", By.xpath("(//span[@class=\"ideal-check\"])[5]"));
		private static ListBox _lstCourtesyCar = new ListBox("Courtesy Car", By.xpath("//select[@id='courtesycar']"));
		private static Button _btnNextPrice = new Button("Next", By.xpath("//button[@id='nextselectpriceoption']"));
		
		// Process data with the elements using a method of the elements
		public static void setStartDate(String startdate) 
		{
			_txtBoxStartDate.setText(startdate);
		}
		
		public static void selInsuranceSum(String insurancesum) 
		{
			_lstInsuranceSum.selectByVisibleText(insurancesum);
		}
		
		public static void selMeritRating(String rating) 
		{
			_lstMeritRating.selectByVisibleText(rating);
		}
		
		public static void selDamageInsurance(String damageinsurance) 
		{
			_lstDamageInsurance.selectByVisibleText(damageinsurance);
		}
		
		public static void selOptionalProducts() 
		{
			_chkOptionalProducts.click();
		}
		
		public static void selCourtesyCar(String courtesycar) 
		{
			_lstCourtesyCar.selectByVisibleText(courtesycar);
		}
				
		public static void clickNextPriceBtn() 
		{
			_btnNextPrice.click();
		}

	}
	
	public static class priceSection
	{
		// Locate elements
		private static RadioButton _rdoUltimate = new RadioButton("Ultimate", By.xpath("(//label[@class=\"choosePrice ideal-radiocheck-label\"])[4]"));
		private static Button _btnNextQuote = new Button("Next", By.xpath("//button[@id='nextsendquote']"));
		
		// Process data with the elements using a method of the elements
		public static void selUltimate() 
		{
			_rdoUltimate.click();
		}
		
		public static void clickNextQuoteBtn() 
		{
			_btnNextQuote.click();
		}
		
	}
	

	public static class sendQuoteSection
	{
		// Locate elements
		private static TextBox _txtBoxEmail = new TextBox("E-mail", By.xpath("//input[@id='email']"));
		private static TextBox _txtBoxUsername = new TextBox("Username", By.xpath("//input[@id='username']"));
		private static TextBox _txtBoxPassword = new TextBox("Password", By.xpath("//input[@id='password']"));
		private static TextBox _txtBoxCofirmPassword = new TextBox("Confirm Password", By.xpath("//input[@id='confirmpassword']"));
		private static Button _btnSend = new Button("Next", By.xpath("//button[@id='sendemail']"));
		
		// Process data with the elements using a method of the elements
		public static void setEmail(String email) 
		{
			_txtBoxEmail.setText(email);
		}
		
		public static void setUsername(String username) 
		{
			_txtBoxUsername.setText(username);
		}
		
		public static void setPassword(String password) 
		{
			_txtBoxPassword.setText(password);
		}
		
		public static void setConfirmPassword(String confirmpassword) 
		{
			_txtBoxCofirmPassword.setText(confirmpassword);
		}
		
		public static void clickSendBtn() 
		{
			_btnSend.click();
		}
	}
	
	public static class emailSuccess
	{
		// Locate elements
		private static Element _alrtEmailSuccess = new Element("Sending e-mail success", By.tagName("h2"));
		private static Button _btnYes = new Button("Next", By.xpath("//button[@class='confirm']"));
		
		// Process data with the elements using a method of the elements
		public static void vrfyEmailSuccessLbl() 
		{
			_alrtEmailSuccess.verifyDisplayed();
		}
		
		public static void clickYes() 
		{
			_btnYes.click();
		}
	}	
}

/* TestData.java dataobject */

package com.seleniumframework.dataobjects;

import java.io.IOException;
import com.seleniumframework.core.DataTable;
import jxl.read.biff.BiffException;

public class TestData {
	
	public static class Urls 
	{
		public static String siteUrl() throws BiffException, IOException 
		{
			return DataTable.getCellValue("URL", 1);
		}
	}
	
	public static class PurchaseInfo
	{	
		public static class VehicleDataInfo
		{
			public static String Make() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Make", 1);
			}

			public static String EnginePerformance() throws BiffException, IOException 
			{
				return DataTable.getCellValue("EnginePerformance", 1);
			}
			
			public static String ManufactureDate() throws BiffException, IOException 
			{
				return DataTable.getCellValue("ManufactureDate", 1);
			}

			public static String SeatNumbers() throws BiffException, IOException 
			{
				return DataTable.getCellValue("SeatNumbers", 1);
			}

			public static String FuelType() throws BiffException, IOException 
			{
				return DataTable.getCellValue("FuelType", 1);
			}

			public static String ListPrice() throws BiffException, IOException 
			{
				return DataTable.getCellValue("ListPrice", 1);
			}

			public static String LicensePlateNumber() throws BiffException, IOException 
			{
				return DataTable.getCellValue("LicensePlateNumber", 1);
			}

			public static String AnnualMileage() throws BiffException, IOException 
			{
				return DataTable.getCellValue("AnnualMileage", 1);
			}
		}
	
  
		public static class InsurantDataInfo
		{
			public static String FirstName() throws BiffException, IOException 
			{
				return DataTable.getCellValue("FirstName", 1);
			}
			
			public static String LastName() throws BiffException, IOException 
			{
				return DataTable.getCellValue("LastName", 1);
			}
			
			public static String DateOfBirth() throws BiffException, IOException 
			{
				return DataTable.getCellValue("DateOfBirth", 1);
			}
			
			public static String StreetAddress() throws BiffException, IOException 
			{
				return DataTable.getCellValue("StreetAddress", 1);
			}
			
			public static String Country() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Country", 1);
			}
			
			public static String ZipCode() throws BiffException, IOException 
			{
				return DataTable.getCellValue("ZipCode", 1);
			}
			
			public static String City() throws BiffException, IOException 
			{
				return DataTable.getCellValue("City", 1);
			}
			
			public static String Occupation() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Occupation", 1);
			}
		}
		
    
		public static class ProductDataInfo
		{
			public static String StartDate() throws BiffException, IOException 
			{
				return DataTable.getCellValue("StartDate", 1);
			}
			
			public static String InsuranceSum() throws BiffException, IOException 
			{
				return DataTable.getCellValue("InsuranceSum", 1);
			}
			
			public static String MeritRating() throws BiffException, IOException 
			{
				return DataTable.getCellValue("MeritRating", 1);
			}
			
			public static String DamageInsurance() throws BiffException, IOException 
			{
				return DataTable.getCellValue("DamageInsurance", 1);
			}
			
			public static String CourtesyCar() throws BiffException, IOException 
			{
				return DataTable.getCellValue("CourtesyCar", 1);
			}
		}
		
    
		public static class SendQuoteInfo
		{
			public static String Email() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Email", 1);
			}
			
			public static String Username() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Username", 1);
			}
			
			public static String Password() throws BiffException, IOException 
			{
				return DataTable.getCellValue("Password", 1);
			}

			public static String ConfirmPassword() throws BiffException, IOException 
			{
				return DataTable.getCellValue("ConfirmPassword", 1);
			}
			
			public static String EmailSuccess() throws BiffException, IOException 
			{
				return DataTable.getCellValue("EmailSuccess", 1);
			}
		}
	}		
}


/*

FRAMEWORK STRUCTURE
1.	Core package
It contains utility classforhandling web browsers on different platform, accessing data source, capturing screenshots, generating customized readable logs as well as the report.28 

2.	Data Objects package
Contains class to create data objects which will store the value from the data source (xsl).
 
3.	Web Elements package
Contains class for web page elements (e.g. button, textbox, ..) and all available actions that we can perform on the element (e.g. click, enter, ..)

4.	Page Objects package
Contains class which are representation of each unique web pages. This is where element locators (e.g. id, name, xpath, etc.) is assigned to a web element to create the page objects.
Reusable methods for a specific page object actions is also created here which is used in developing the test scripts.

5.	Tests package
Use Page Objects and Data Objects to create a test script and form a test scenario.


SETTING UP MAVEN

Apache Maven is a software project management and comprehension tool that can
manage a project's build, reporting and documentation from a central piece of
information. It will download the java bindings and all its dependencies, and will
create the project for you using a project configuration file.

How to setup projects to Maven:
Step 1: Follow the step by step guide in configuring your machine with Maven
Step 2: Open Eclipse application.
Step 3: Right click on the project file > Configure > click “Convert to Maven Project”
Step 4: Click Finish button and wait for the loading to finish.
Step 5: A new file, “pom.xml”, will be created under the project files.

In the pom.xml file we can manage the configurations settings for the project file. We’ll be adding the jar files needed for the project but first removed the jar file added in the project library.

Step 1: We add the “dependencies” tag first in the pom.xml and then in between those tags we add all the dependencies needed for the
project.

Step 2:
In the Maven dependencies repositories website ( http://mvnrepository.com/ com/) you can search for the jar files needed and copy the code given for maven.

Step 3: Paste the copied code between the “dependencies” tag, then save the pom.xml
file. 

After saving you can notice that the project is currently building, it means that Maven started downloading the added
dependency.

All the files that will be downloaded by Maven will be stored in the “repository” folder, you can find it in
C: Users \\< eid>\\.m2
 

How to setup existing Maven projects

Step 1: Right click on the Package Explorer tab then click “Import”

Step 2: Click “Maven” > click “Existing Maven Projects” then click Next button

Step 3: Click the “Browse…” button

Step 4: Find and select the “SeleniumProject” folder (path: C:\Workspace) then click OK button.

Step 5: The selected folder should appear in the Projects. Click Finish button.

Step 6: The project will now be displayed in the Project Explorer tab. Maven will start downloading the files needed for the project file. Wait for the build of the codes to finish which is displayed on the bottom-right corner of Eclipse.

Step 7: Right click on the project > Maven > click “Update Project…”

Step 8: Click the checkbox “Force Update of Snapshots/Releases” then click OK button.

Step 9: Maven will start downloading the files needed for the project file. Wait for the build of the codes to finish which is displayed on the bottom-right corner of Eclipse.

Step 10: Make sure that there are no errors displayed in the “Problems” tab.

*/

