
// This Selenium test script was written by Claive Alvin P. Acedilla

/******************************************
SuccesfulPurchaseOfItems.java tests script
*******************************************/

package com.seleniumbootcampframework.tests;

import org.testng.annotations.Test;
import com.seleniumbootcampframework.core.Browser;
import com.seleniumbootcampframework.core.Log;
import com.seleniumbootcampframework.dataobjects.TestDataExam;
import com.seleniumbootcampframework.pageobjects.TricentisHome;
import com.seleniumbootcampframework.pageobjects.AutomobileInsurancePage;

// Inherit Browser.java class
public class SuccesfulPurchaseOfItems extends Browser 
{
	@Test
	public void SuccessfulPurchaseOfItems() throws Exception 
	{
		Log.setStoryName("Purchase Vehicle");
		
		// 1. Navigate to URL using Browser class driver
		getDriver().get(TestDataExam.Urls.tricentisUrl());
		
		// Run Test scripts by calling base page element methods and TestDataExam base test values
		
		// 2. Verify vehicle navigation links 
		TricentisHome.navSection.verifyAutomobileNavLink();
		TricentisHome.navSection.verifyTruckNavLink();
		TricentisHome.navSection.verifyMotorcycleNavLink();
		TricentisHome.navSection.verifyCamperNavLink();
		
		// 3. Click the Automobile hyperlink
		TricentisHome.navSection.clickAutomobileNavLink();
		
		// 4. Verify Automobile Insurance nav links
		AutomobileInsurancePage.navSection.vrfyAutoInsuranceLbl();
		AutomobileInsurancePage.navSection.vrfyVehicleDataNavLink();
		AutomobileInsurancePage.navSection.vrfyInsurantDataNavLink();
		AutomobileInsurancePage.navSection.vrfyProductDataNavLink();
		AutomobileInsurancePage.navSection.vrfyPriceOptionNavLink();
		AutomobileInsurancePage.navSection.vrfySendQuoteNavLink();
		
		// 5. Populate Vehicle Data fields
		AutomobileInsurancePage.vehicleDataSection.selMake(TestDataExam.PurchaseInfo.VehicleDataInfo.Make());
		AutomobileInsurancePage.vehicleDataSection.setEnginePerformance(TestDataExam.PurchaseInfo.VehicleDataInfo.EnginePerformance());
		AutomobileInsurancePage.vehicleDataSection.setDateOfManufacture(TestDataExam.PurchaseInfo.VehicleDataInfo.ManufactureDate());
		AutomobileInsurancePage.vehicleDataSection.selNumOfSeats(TestDataExam.PurchaseInfo.VehicleDataInfo.SeatNumbers());
		AutomobileInsurancePage.vehicleDataSection.selFuelType(TestDataExam.PurchaseInfo.VehicleDataInfo.FuelType());
		AutomobileInsurancePage.vehicleDataSection.setListPrice(TestDataExam.PurchaseInfo.VehicleDataInfo.ListPrice());
		AutomobileInsurancePage.vehicleDataSection.setLicensePlateNumber(TestDataExam.PurchaseInfo.VehicleDataInfo.LicensePlateNumber());
		AutomobileInsurancePage.vehicleDataSection.setAnnualMileage(TestDataExam.PurchaseInfo.VehicleDataInfo.AnnualMileage());
		
		// 6. Click Next button
		AutomobileInsurancePage.vehicleDataSection.clickNext();

		// 7. Populate Insurant Data fields
		AutomobileInsurancePage.insurantDataSection.setFirstName(TestDataExam.PurchaseInfo.InsurantDataInfo.FirstName());
		AutomobileInsurancePage.insurantDataSection.setLastName(TestDataExam.PurchaseInfo.InsurantDataInfo.LastName());
		AutomobileInsurancePage.insurantDataSection.setDateOfBirth(TestDataExam.PurchaseInfo.InsurantDataInfo.DateOfBirth());
		AutomobileInsurancePage.insurantDataSection.selGender();
		AutomobileInsurancePage.insurantDataSection.setStreetAddress(TestDataExam.PurchaseInfo.InsurantDataInfo.StreetAddress());
		AutomobileInsurancePage.insurantDataSection.selCountry(TestDataExam.PurchaseInfo.InsurantDataInfo.Country());
		AutomobileInsurancePage.insurantDataSection.setZipCode(TestDataExam.PurchaseInfo.InsurantDataInfo.ZipCode());
		AutomobileInsurancePage.insurantDataSection.setCity(TestDataExam.PurchaseInfo.InsurantDataInfo.City());
		AutomobileInsurancePage.insurantDataSection.selOccupation(TestDataExam.PurchaseInfo.InsurantDataInfo.Occupation());
		AutomobileInsurancePage.insurantDataSection.selHobbySpeeding();
		AutomobileInsurancePage.insurantDataSection.selHobbySkydiving();

		// 8. Click Next button
		AutomobileInsurancePage.insurantDataSection.clickNextProductBtn();
		
		// 9. Populate Product Data Fields
		AutomobileInsurancePage.productDataSection.setStartDate(TestDataExam.PurchaseInfo.ProductDataInfo.StartDate());
		AutomobileInsurancePage.productDataSection.selInsuranceSum(TestDataExam.PurchaseInfo.ProductDataInfo.InsuranceSum());
		AutomobileInsurancePage.productDataSection.selMeritRating(TestDataExam.PurchaseInfo.ProductDataInfo.MeritRating());
		AutomobileInsurancePage.productDataSection.selDamageInsurance(TestDataExam.PurchaseInfo.ProductDataInfo.DamageInsurance());
		AutomobileInsurancePage.productDataSection.selOptionalProducts();
		AutomobileInsurancePage.productDataSection.selCourtesyCar(TestDataExam.PurchaseInfo.ProductDataInfo.CourtesyCar());
		
		// 10. Click Next button
		AutomobileInsurancePage.productDataSection.clickNextPriceBtn();
		
		// 11. Select Ultimate Price radio
		AutomobileInsurancePage.priceSection.selUltimate();
		
		// 12. Click Next button
		AutomobileInsurancePage.priceSection.clickNextQuoteBtn();
				
		
		// 13. Populate Send Quote data fields
		AutomobileInsurancePage.sendQuoteSection.setEmail(TestDataExam.PurchaseInfo.SendQuoteInfo.Email());
		AutomobileInsurancePage.sendQuoteSection.setUsername(TestDataExam.PurchaseInfo.SendQuoteInfo.Username());
		AutomobileInsurancePage.sendQuoteSection.setPassword(TestDataExam.PurchaseInfo.SendQuoteInfo.Password());
		AutomobileInsurancePage.sendQuoteSection.setConfirmPassword(TestDataExam.PurchaseInfo.SendQuoteInfo.ConfirmPassword());
		
		// 14. Click Send button
		AutomobileInsurancePage.sendQuoteSection.clickSendBtn();
		
		// 15. Verify send email success
		AutomobileInsurancePage.emailSuccess.vrfyEmailSuccessLbl();
		
		// 16. Click Yes button
		AutomobileInsurancePage.emailSuccess.clickYes();
    
	}	
}


/*****************************
TricentisHome.java pageobject
******************************/

package com.seleniumbootcampframework.pageobjects;

import org.openqa.selenium.By;

// Inherit element classes
import com.seleniumbootcampframework.webelements.Button;
import com.seleniumbootcampframework.webelements.Element;
import com.seleniumbootcampframework.webelements.Link;
import com.seleniumbootcampframework.webelements.TextBox;

public class TricentisHome {
	
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

/***************************************
AutomobileInsurancePage.java pageobject
****************************************/

package com.seleniumbootcampframework.pageobjects;

import org.openqa.selenium.By;

// Inherit element classes
import com.seleniumbootcampframework.webelements.Button;
import com.seleniumbootcampframework.webelements.CheckBox;
import com.seleniumbootcampframework.webelements.Element;
import com.seleniumbootcampframework.webelements.Link;
import com.seleniumbootcampframework.webelements.ListBox;
import com.seleniumbootcampframework.webelements.RadioButton;
import com.seleniumbootcampframework.webelements.TextBox;

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

/****************************
TestDataExam.java dataobject
*****************************/

package com.seleniumbootcampframework.dataobjects;

import java.io.IOException;
import com.seleniumbootcampframework.core.DataTable;
import jxl.read.biff.BiffException;

public class TestDataExam {
	
	public static class Urls 
	{
		public static String tricentisUrl() throws BiffException, IOException 
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


