Chapter 00 Introduction
=======================

What is a scripting language
------------------------------
Scripting language is an interpreted language by an interpreter engine.

Javascript is one of the languages of webpages 
HTMl markup language for content structure
CSS stylesheet language for presentation
Javascript programming language for web page behavior

Javasript is a client-side language
------------------------------------
Javacript is run from the client-side browser interpreter engine

Other uses of Javascript
-------------------------

Issues with a client-side language
------------------------------------
Javascript can be disabled
Can't access local files
Cant' directly access database
Can't access hardware (USB, etc)

Javascript history
-------------------
1995 Livescript
1996 Javascript Netscape 2, IE 3 Jscript
1997 ECMAScript
1999 ECMAScript 3
2009 ECMAScript 5 published (Backward compatible to ECMAScript3)

What do you need to write Javascript?
----------------------------------------
You just need a text editor

Step 1. Have a web page as the container for javascript
Step 2. Use <script> tag to call javascript inside html


Tools
-----
1. Text Editor or IDE
2. Firefox with firebug add on
3. 


Chapter 02 Core Javascript Syntax
==================================

Javascript structure
---------------------
Use <script> tag to call javascript inside html

Javascript is interpreted, not compiled
----------------------------------------

Javascript is case sensitive
-----------------------------

Statements
------------
Written in one line ended with semicolon

Pseudocode
-------------
change color of headline
calculate age
move image
hide menu
alert "important message

Javascript is whitespace insensitive
-------------------------------------

Javascript comments
-------------------
// this is a comment

Execution Order
----------------
Code is read from top to bottom

<script> tag can be place in head element or body of html code

Location of the <script> tag
-------------------------
Javascript better be placed on a separate file for easy maintenance

Put script tag at the bottom of the body
<script src="myscript.js" type="text/javascript">
</script>

Variables
-----------
Variables are containers with names

var year;
var customerEmail;
var todaysDate;
var foo;

Creating variables
-------------------
var year;     // no value which mean undefined
year = 2011;     //defined with value

Variable names are case sensitive
----------------------------------
var x = 200;
X = 210;     // wrong 

Multiple variables
--------------------
You can separate multiple variables in one line with commas
var year, month, day;

Variable data types
--------------------
Javascript is weak type language
Varibles can hold any type of data

var myVariable
myVariable = 200;    // it can hold number
myVariable = "Hello";    //it can hold string
myVariable = 'Hello';
myVariable = true;    //it can hold boolean
myVariable = false;

Conditions
-----------
    if ( condition ) {

    }

if (a < 50) {        // check if true 
    //code goes here

}

( c == 9)

code block = inside the braces { }

var amount = 500;

if (amount < 1000) {
    alert ("Its less than 1000");
}

if (     ) {
  // code goes here
  // ...
} else {
  //otherwise, different code
    if ( ){
        //neste if
    }
}

Dont nest if to deep because it is difficult to read and understand. Break your code instead with different functions

Terminology
------------
    parenthesis ( )
    brackets [ ]
    braces { }

Operators
----------

Arithmetic operators
---------------------
 + - / *

Assignment
-----------
result = a + b;

score = score + 10;
or

score += 10;

+= -= /= *=

Operator precedence
---------------------
Multiplation and Division are important than Addition and Subraction

User parenthesis the way you want to computer

Assignment instead of Equality
-------------------------------
var a = 5;
var b = 10;

if (a = b) {

    // always true
}

= assignment
== equality
=== strict equality

Always use strict equality to check equality in javascript

var a = 5;
var b = "5";

if ( a === b) {
    alert("Yes, they're equal");
} else {
    alert("They are NOT equal");
}

Comparison
-----------
if (a === b) 
if (a !== b)
if ( a > b )
if (a < b)
if (a >= b)
if (a <=b)

if (a === b && c === d) { ...
if (a === b or c === d) { ...
if (( a > b) && (c < d)) { ...

Modulus
--------
var year = 2003;
var remainder = year % 4; // % is the modulus 

Increment/Decrement
--------------------
a = a + 1;
a += 1;
a++;
++a;

a = a - 1;
a -= 1;
a--;
--a;

Prefix/Postfix
-----------------
var a = 5; 
alert(++a);

Ternary
--------
condition ? true : false

var playerOne = 500;
var playerTwo = 600;

var highScore;

if (playerOne > playerTwo) {
    highScore = playerOne;
} else {
    highScore = playerTwo;
}

// can be written 

var highScore = (playerOne > playerTwo) ? playerOne : playerTwo;

console.log to test alert() messages in firebug
-----------------------------------------
var foo = 10;
var bar = 20;

if (foo < bar) {
    console.log("foo is less than bar");
    console.log("and here's a second message");    
    console.log("and here's a third message");
}

console.debug
console.info
console.warn
console.error

Working with Loops
-------------------
repeat 

While loop
-----------

var a = 1;

while (a < 10) {
    console.log(a);
    a++;
}

Do... While loop
------------------
var a = 1;

do {
    console.log(a);
    a++;
} while (a < 10);

// will always happen at least once


For loop
---------
For loop is a generalization of While loop

for (i = 1; i < 10, i++) {
    // do stuff
    // do stuff
    // do stuff
    // etc..
}


Break
------
for (var i = 1; i < 5000; i++) {
    // do stuff
    (if == 101) {
        break;
    }
    // do break
}
// break jumps out of the loop

Continue
-----------
for (var i = 1; i < 5000; i++) {
    //do stuff
    if (i % 5 == 0) {
        continue; // go back to parent loop
    }
    // do second stuff

}

Functions in javascript
------------------------
Use descriptive verbs when naming functions

function createMessage {
    console.log("we're in the function!");
    //loops, if statements, anything!
    // ...
}

// sometime later call the function
myFunction();
myFunction();
    
Define functins before you call them

Functions with parameters
--------------------------
                     parameters
function myFunction (x, y) {
    var myVar = x * y;
    console.log (myVar);
}

myFunction(754, 436);
myFunction(123,-732);
alert("Hello world"); //built-in javascript function

var myresult = myFunction(6,9);

Parameter mismatch
--------------------
function calculateLoan(amount, months, interest, name){
    //lots of code
}

myFunction(10000,60,7,"Sam Jones"); //correct
myFunction(10000,60,7,"Sam Jones", "Something extra"); // extras are ignored
myFunction(1000,60); //missing are passed as "undefined"

Varible Scope
--------------
function simpleFunction(){
    //lots of code
    var foo = 500;    //foo is local variable to simpleFunction function
    //lots of code
    console.log(foo);
}

simpleFunction();
console.log(foo);    //undefine

Declare variable outside of function to declare as global variable


Chapter 03 Types and Objects
=============================

Creating Arrays
----------------
var singleValue;
singleValue = 99;

var multipleValues = [ ];

multipleValues[0] = 50;    //access content of array through index
multipleValues[1] = 60;
multipleValues[2] = "Mouse"

//or

var multilpleValues[50, 60, "Mouse"];


console.log(multipleValues[2]);

//javascript has a 0 index arrays

Creating arrays-longhand
---------------------------
var multipleValues = [ ];
var multipleValues = new Array(); //arrays are objects
var multipleValues = Array();
var multipleValues = Array(5);


Array properties
-----------------
var multipleValues = [10,20,30,40,50];

console.log(multipleValues.length); //length is 5

Array methods
--------------
someObject.someMethod();

var multipleValues = [10,20,30,40,50];
    multipleValues.reverse();
            .join();
            .sort();

console.log(reversedValues.join() );     //50,40,30,20,10


Arrays are everywhere
---------------------

var myArrayOfLinks = document.getElementsByTagName("a");
// get number of links tag in a page

Numbers
--------
var x = 200;

Javascrip numbers are 64-bit floating point numbers.

x = 200.5;

Addition vs Concatenation
---------------------------
var foo = 5;
var bar = 5;
console.log(foo + bar); //10

var foo = "5";
var bar = "5";
console.log(foo + bar); //55

var foo = 5;
var bar = "b";
console.log(foo * bar); // NaN = not 
a number


Not A Number
-------------
var foo = "55"; //could be "abc"
var myNumber = Number(foo); //make it a number

if(isNaN(myNumber)){
    console.log("It's not a number!");
}

if(!isNaN(myNumber))

Using the Math object
---------------------
var x = 200.6;
var y = Math.round(x);    // 201

var a = 200, b = 10000, c = 4;
var biggest = Math.max(a,b,c);
var smallest = Math.min(a,b,c);

Math.PI Math.random() .sqrt() .log()


Strings
---------

Quotes inside Quotes
----------------------
var phrase = 'Don't mix your quotes.'; //wrong
var phrase = "Don't mix your quotes."; //correct

var phrase = "He said "that's fine," and left.";  //wrong
var phrase = "He said \"that's fine.\" and left."; // correct

String properties
-------------------
String can be treated as objects
Strings are treated as array of characters
var phrase = "This is a simple phrase.";
console.log(phrase.length);

var phrase = "This is a simple phrase.";
console.log(phrase.toUpperCase());


String methods-split
--------------------
var phrase = "This is a simple phrase.";
var words = phrase.split(" ");

0    This
1    is
2    a
3     simple
4    phrase

String method Index
---------------
var phrase = "We want a groovy keyword";
var position = phrase.indexOf("groovy"); //10

if (phrase.indexOf("DDDD") == -1) {
    console.log("That word does not occur.");

String methods slice
---------------------
var phrase = "Yet another phrase.";

var segment = phrase.slice(6,5);

.substring() .substr()


String comparison
---------------------
var str1 = "Hello";
var str1 = "hello";

//str1 != str2

if ( str1.toLowerCase() == str2.toLowerCase()) {
    console.log("Yes, equal");
}

var str1 = "aadvark";
var str2 = "beluga";

if (str1 < str2) { ...    //

var str1 = "aadvark";
var str2 = "Beluga";

if (str1 < str2) { ... // false!

ABCD... is less than abcd...

String reference
--------------------
developer.mozillar.org/en/javascript/reference

Working with Dates
-------------------
var today = new Date();  // create new Date and name date object as "today"

// year, month, day
var y2k = new Date(2000,0,1);

//year, month, day, hours, minutes, seconds
var y2k = new Date(2000,0,1,0,0,0);

Get methods of the date object
----------------------------------'
var today = new 
Date();

today.getMonth();      // returns 0-11
today.getFullYear();  // YYYY (not zero-based)
today.getYear();    // deprecated
today.getDate();    // 1-31 day of month
today.getDay();         // 0-6 day of thet
 week wher 0 is Sunday
today.getHours();    //0-23
today.getTime();    //milliseconds since 1/1/1970

var myDate = new Date(1906,11,9);

console.log("Grace Hopper was born on: ", myDate.getDay() );

Set methods of the Date object
--------------------------------
var today = new Date();

today.setMonth(5);
today.setFullYear(2012);
today.setDay(0);
// etc/

Comparing Dates
-----------------
var date1 = new Date(2000,0,1);
var date2 = new Date(2000,0,1);

if ( date1 == date2)  { .. //false!~

if (date1.getTime() == date2.getTime()) {
    // true

Objects in Javascript
----------------------
When we create an array or a date, we are creating objects
var myArray = [10,20,30,"Forty",60];
console.log(myArray.length);

var todaysDate = new Date(); 
var ms = todaysDate.getTime(); // functions belong to Date object

DOM or Document Object model is the object that contain the html elements

We can even create our own objects

Object Creation
-----------------
Objects is a container that gather data and behavior

Objects allow us to gather variables and functions and give it a name

var playerName = "Fred";
var playerScore = "10000";
var playerRank = 1;

var player = new Object();
player.name = "Fred";    // .name is property of object
player.score = 10000;
player.rank = 1;

Object creation: shorthand
----------------------------

var player1 = { name: "Fred", score: 1000, rank: 1};
var player2 = { name: "Sam", score: 1000000, rank: 5};

var player1 = { name: "Fred", score: 1000, rank: 1};
var player2 = { name: "Sam", score: 1000000, rank: 5};

function playerDetails(){
    //display information about each player
    console.log(this.name + "has a rank of: " + this.rank + " and a score of " + this.score);

}

player1.logDetails = playerDetails; // associate object to function
player2.logDetails = playerDetails;

player1.logDetails();
player2.logDetails();



Chapter 04 Understanding the Document Object Model
===================================================

What is DOM?
-------------

Wbat is the Document?
---------------------
The Webpage and the html source

What are the objects?
----------------------
The elements

What is the model?
-------------------
The HTML structure

Tree structure of html

Document Object       Model
webpage   pieces  agreed-upon set of terms

What you an do with the DOM
----------------------------
-Get the title text
-Get the second paragraph
-Get the third link in the menu and set its CSS to display:none
-Change the background color of all paragraphs with a class of "important"
-Get all the <li> elements in the last unordered list
-Find the image with an id of "logo" and move it 40 pixels to the right
-Change a link so it performs a Javascript function when clicked
-Crete a new unordered list and insert between first and second paragraphs

Nodes and elements
--------------------
DOM think webpage elements as nodes

Even the smallest document has many nodes
--------------------------------------------

Node types
------------
There are 12 types of elements in the DOM but we are only interested in three
Node.ELEMENT_NODE == 1
Node.ATTRIBUTE_NODE == 2
Node.TEXT_MODE == 3

Element, Attribute and Text Nodes
-----------------------------------

<ul id="optionList">
    <li>this is the first option</li>
    <li>this is the first option</li>
    <li>this is the first option</li>
</ul>

ul         element node
id="optioList"    attibute node
li        element node
li        element node
li         element node
This is ...    text node
This is ...    text node
This is ...    text node
    
Element nodes don't contain text
---------------------------------
p        element node
li        element node
h1        element node
text here    text node    //text node is separate node from the parent element node
list item here! text node
heading here!    text node


Chapter 05 Working with the Document Object Model
==================================================

How to get and element node
-----------------------------
Get element that is unique in the document. Look for the element that has the id

use getElementById method

document.getElementById("someId");


Retreiving an element by ID
-----------------------------
Create a variable and assign get element method

var myElement = document.getElementByID("abc");

How to get elements without ID
document.getElementsByTagName("a"); 

var myListItems = document.getElementsByTagName("li");


script.js

var mainTitle = document.getElementById("mainTitle");

console.log("This is an element of type: ", mainTitle.nodeType);
console.log("the Inner HTML is ", mainTitle.innerHTML);
console.log("Child nodes: ", mainTitle.childNodes.length);

var myLinks = document.getElementsByTagName("a");
console.log("Links: ", myLinks.length);


Restricting elements to retrieve
----------------------------------
var myListItems = document.getElementByTagName("li");
var myFirstList = document.getElementByID("abc");        //filter by retreiving unordered list "abc" by id 
var limitedList = myFirstList.getElementsByTagName("li");    //retrieve list in from unordered list variable


Changing DOM Content
---------------------
Step 1. Get the element first. Make a variable to handle the element
Attribute and text nodes comes next

Changing attributes
--------------------
myElement.getAttribute("align")

var mainContent = document.getElementById("mainContent");
mainContent.setAttribute("align","right");

mainTitle = document.getElementById("mainTitle");
console.log(mainTitle.innerHTML);

var sidebar = document.getElementById("sidebar");
console.log(sidebar.innerHTML);

//var arrayOfH1s = mainContent.getElementsByTagName("h1");
//arrayOfH1s[0].innerHTML = "This is a new title";


Creating DOM Content
====================
1. create the element
2. add it to the document

var myNewElement = document.createElement("li");
myNewElement.appenChild(myNewElement);

Creating Text Nodes
--------------------
var myText = document.createTextNode("New list item text");
myNewElement.appendChild(myText);

//create the elements
var newHeading = document.createElement("h1");
var newParagraph = document.createElement("p");

// to add content, either use innerHTML
newHeading.innerHTML = "Did You Know?";
newParagraph.innerHTML = "California produces over 17 million gallons of wine each year!";

// OR create child nodes manually
var h1Text = document.createTextNode("Did You Know?");
var paraText = document.createTextNode("California produces over 17 million gallons of wine each year!");
// and add them as child nodes to the new elements
newHeading.appendChild(h1Text);
newParagraph.appendChild(paraText);

// and we still need to attach them to the document!
document.getElementById("trivia").appendChild(newHeading);
document.getElementById("trivia").appendChild(newParagraph);

Alternatives to appenchild
-----------------------------
parent.insertBefore(newElement, existingElement);

var myNewElement = document.createElement("li");
var secondItem = myElement.getElementsByTagName("li")[1];
myElement.insertBefore(myNewElement, secondItem);


Chapter 06 Working with Events and Event Listeners
===================================================

Events and Event Listeners
---------------------------

What is an event
----------------
Events are already happening
Its up to you to decide which event you care

Event Names
------------
onload
onclick
onmouseover
onblur
onfocus

Handling Events: Method 1
-----------------------------
<button onclick="alert('Hello, world');">
    Run Some Javascript
</button>

Handling Events: Method 2
----------------------------
myelement.onclick = function() {    // function has no name because onclick is already a function
    // your event handler code
    // ...
    // ...
};    // event is considered one statement


Handling Events: Method 3
----------------------------
document.addEventListener('click', myFunction, false);

// Internet Explorer 8 and previous versions does not support addEventListener

// Internet Explorer 8 and previous
document.attachEvent('onclick', myFunction);

Cross-browser add event helper methods
---------------------------------------
function addCrossBrowserEventLister (elementName, eventName, functionName) {
    // does the addEventListener function exist?
    if (elementName.addEventListener) {
      //yes - use it
      elemenName.addEventListener(eventName, functionName, false);
      return true;
    } else {
      //otherwise use attachEvent
      elementName.attachEvent("on" + eventName, functionName);
      return true;
    }
}

For cross-browser functions use JQuery (or another library) instea of writing your own cross-browser code.

//document.onclick = function(){
//    alert("You clicked somewhere in the document")    
//    }

var myImage = document.getElementById("mainImage");
myImage.onclick = function(){
    alert("You clicked the image")    
}

// use the commented-out code for reference, or just write your own. 

//document.onclick = function() {
//    alert("You clicked somewhere in the document");
//};

function prepareEventHandlers() {    
    var myImage = document.getElementById("mainImage");
    myImage.onclick =  function() {
        alert("You clicked the image");
    }
}

window.onload = function() {    //catch in order for script to run after webpage is loaded
    // prep anything we need to
    prepareEventHandlers();
};


Events working with Forms Focus/Blur
---------------------------------------

var emailField = document.getElementById("email");

emailField.onfocus = function() {
    if ( emailField.value == "your email") {
        emailField.value = "";
    }
};

emailField.onblur = function() {
    if ( emailField.value == "") {
        emailField.value = "your email";
    }
};



Timers
-------
// Two methods for timers - setTimeout and SetInterval (single / repeating)

function simpleMessage() {
    alert("This is just an alert box");
}

// settimeout is in milliseconds
//setTimeout(simpleMessage,5000)    // call simpleMessage after 5 seconds

var myImage = document.getElementById("mainImage");

var imageArray = ["_images/overlook.jpg","_images/winery_sign.jpg","_images/lunch.jpg",
                  "_images/bigSur.jpg","_images/flag_photo.jpg","_images/mission_look.jpg"];
var imageIndex = 0;

function changeImage() {
    myImage.setAttribute("src",imageArray[imageIndex]);
    imageIndex++;
    if (imageIndex >= imageArray.length) {
        imageIndex = 0;
    }
}

// setInterval is also in milliseconds
var intervalHandle = setInterval(changeImage,5000);

myImage.onclick = function() {
    clearInterval(intervalHandle);    
}


Chapter 07 Debugging
=====================

Common Errors
--------------
1. Let your javascript debugger open like firebug in firefox
2. Syntax errors
3. 

// Issue 1: Syntax errors
/*
function myFunction( {                            // missing closing function parenthesis
    console.log("You called myFunction);    // missing closing double quotes
}

window.onload = function() 
    myFunction();
}
*/

// Issue 2: calling a non-existent function
/*
function myFunction() {
    console.log("You called myFunction");
}

window.onload = function() {        
    myfunction();        // wrong spelling of function name
}
*/

// Issue 2b: typos very common with DOM methods
//var x = document.getElementByID("something");        // wrong syntax of getElementById

// Issue 2c: using a non-existent object method
//var myArray = ["one","two","three"];
//console.log(myArray.revers());                // wrong spelling of reverse method



// Issue 4: using document.getElementById before the element is part of the DOM.
// make sure the DOM is loaded - use window.load
//var myImage = document.getElementById("someImage");

// Issue 5 - assignment instead of equality
// This is NOT technically an error
/*
var a = 10;
var b = 20;

if ( a = b) {    // assignment instead of equality
    console.log("Something is wrong with the universe.");
} else {
    console.log("This is what I expect!")
}
*/

// Issue 6: missing parameters in function calls:
// This is NOT an error - it's just an unexpected result.

function calculateSum(a,b,c) {
    return a + b + c;
}

var result = calculateSum(500,1000);    // one paramater passed is missing
console.log(result);



Firebug
========
Console view
HTML view 
--you can inspect HTMl elements in DOM view
CSS view
Script panel
  --let you see script that you put in the document
  --you can do javascript debugging. You can set breakpoints, step into the code, stepping out of loop, step over a function or skipping, see variable values on watch window, continue to read whole code 
DOM view
  --you can check child nodes and properties


Debugging
----------
var messageArray = ["The true heart of California","Tours as diverse as California itself","Explore our world your way"];
var messageIndex = 0;

function deeperFunction() {
    // perform loop
    for (var i = 0; i < 500; i++) {
        // do stuff.
        var foo = i * (Math.random());
        var bar = foo;
        // more exciting code.
    }
}

function simpleFunction() {
    // jump into a deeper function
    deeperFunction();
    // now grab the message and change it.
    var newMessage = messageArray[messageIndex];
    var messageElement = document.getElementById("mainMessage");
    messageElement.innerHTML = newMessage;
    messageIndex++;
    if (messageIndex > messageArray.length) {  // should be >= to equal to the last item of the Array
        messageIndex = 0;
    }
}

function changeMessage() {
    simpleFunction();
}

window.onload = function() {
    setInterval(changeMessage,4000);
};



Chapter 08 Building Smarter Forms
==================================

Enhancing forms with javascript
---------------------------------

Getting form and forms elements
---------------------------------
document.forms.frmContact

document.forms.frmContact.name

Textfields
-----------
main property
value property
myTextField.value

main events
onfocus
onblur
onchange
onkeypress
onkeyup
onkeydown

Checkboxes and radio buttons
-----------------------------
main property
myCheckBox.checked // true or false

main events
onclick
onchange

Select lists
-------------
main property
mySelect.type // select-one or select multiple

select-one
mySelect.selectedIndex

select-multiple
mySelect.options[x].selected  // true or false

main events onchange


Form events
------------
main event
onsubmit


// handle the form submit event
function prepareEventHandlers() {
    document.getElementById("frmContact").onsubmit = function() {
        // prevent a form from submitting if no email.
        if (document.getElementById("email").value == "") {
            document.getElementById("errorMessage").innerHTML = "Please provide at least an email address!";
            // to STOP the form from submitting
            return false;
        } else {
            // reset and allow the form to submit
            document.getElementById("errorMessage").innerHTML = "";
            return true;
        }
    };
}

// when the document loads
window.onload =  function() {
    prepareEventHandlers();
};

Show/Hide forms
----------------
function preparePage() {
    document.getElementById("brochures").onclick = function() {
        if (document.getElementById("brochures").checked) {
            // use CSS style to show it
            document.getElementById("tourSelection").style.display = "block";
        } else {
            // hide the div
            document.getElementById("tourSelection").style.display = "none";
        }
    };
    // now hide it on the initial page load.
    document.getElementById("tourSelection").style.display = "none";
}

window.onload =  function() {
    preparePage();
};



Chapter 09 UI Enhancement 
===========================

CSS and Javascript
-------------------

Setting Inline Styles
----------------------
myElement.style.color = "red";
myElement.style.left = "40px";
myElement.style.backgroundRepeat = "repeat-x";


Style property Naming
----------------------
myElement.style.fontWeight = "bold";
myElement.style.backgroundColor = "#193742";

css style naming in javascript becomes camelCase


Setting the Class
------------------
myElement.className = "someCSSclass";

// prevent a form from submitting
function preparePage() {
    document.getElementById("mainContent").onclick = function() {
        if ( document.getElementById("mainContent").className == "example") {
             document.getElementById("mainContent").className = "";
        } else {
           document.getElementById("mainContent").className = "example";
        }
    };
}

window.onload =  function() {
    preparePage();
};

main.css

/* ^3 ------ global classes -------- */
.example {
    color: #fff;
    font-size: 1em;
    text-align: right;
}


Inline styles
--------------
var currentPos = 0;
var intervalHandle;

function beginAnimate() {
    document.getElementById("join").style.position = "absolute";
    document.getElementById("join").style.left = "0px";
    document.getElementById("join").style.top = "100px";
    // cause the animateBox function to be called
    intervalHandle = setInterval(animateBox,50);
}

function animateBox() {
    // set new position
    currentPos+=5;
    document.getElementById("join").style.left = currentPos + "px";
    // 
    if ( currentPos > 900) {
        // clear interval
        clearInterval(intervalHandle);
        // reset custom inline styles
        document.getElementById("join").style.position = "";
        document.getElementById("join").style.left = "";
        document.getElementById("join").style.top = "";
    }
}

window.onload =  function() {
    setTimeout(beginAnimate,5000);
};

<div id="join" class="callOut callOutRight">
        <h1>Sign up!</h1>
        <p>Join our Explorers Program and get access to our monthly newsletter, members-only rates, and blog about your travels!
<a href="explorers.htm" title="Join our community" class="accent">Join here</a></p>
      </div>


Chapter 10 Javascript Best Practices
=====================================

Javascript Style Guides
------------------------
How you should write Javascript

How should you name your variables
Where should you put your braces
How should you call your functions and where should you put them in your code

Your code should be easily readable
Your code should be consistent
You should know accepted best practices

Javascript is easily readable 
------------------------------

Naming Conventions
--------------------
Use meaningful names for variables and functions

Use camelCase for multiword variables and functions
----------------------------------------------------
var highScore;
var evenHigherScore;
function calculate();
function calculateDistance();
function checkFormFields();

createElement
appendChild
getElementById

Objects: Uppercase first letter
--------------------------------
Math Date
var myDate = new Date();

Brace style
-------------
if (x) {
  // ...
} else {
  // ...
}
 
Always use blocks
-------------------
if (x > 500) {
    alert("There's a problem");
    resetEverything();
}

Define your functions before you call them
--------------------------------------------

Guidelines Review
-------------------
Use CamelCase for variables, functions and methods
Open curly braces on the same line
Always use blocks - even if only one line
Define your functions before you call them
Always use semicolons to end statement

Javascript minification
------------------------
Reduce file size
Does not "compile"
Does not intentionally obfuscate

Tools for minification
---------------------------
Google closure compiler

Check javascript code quality
------------------------------

Tools
-----
JSLint


Chapter 11 Javascript Libraries
================================

There are lots of resources in the internet but
JQuery javascript library is the best

Linking to Multiple Javascript Files
-------------------------------------
put script tag right before the closing body tag
Avoid using mutilple javascript file because it is read one at a time

Order is important for script tags
------------------------------------

Intro to JQuery
----------------
go to http://jquery.com and download the jQuery script
Include the jquery script in your webpage

Regular javascript vs jQuery
------------------------------
document.getElementById("myDiv").className = "highlight";
 
      selector
jQuery(#myDiv).addClass("Highlight");
jQuery(".someClass")
jQuery("p")
jQuery("a")
jQuery("p.description")

:first
:last
:contains()

// basic
document.getElementById("mainArticle").className = "highlight";

// use jQuery - basic
//jQuery("#mainArticle").addClass("highlight");

// find all elements with a particular class
//jQuery(".tourDescription").addClass("highlight");

// find all elements with a particular tag
//jQuery("li").addClass("highlight");

// find the last li
//jQuery("li:last").addClass("highlight");

// find any paragraph that contain the word "packages"
//jQuery("p:contains('packages')").addClass("highlight");

// EFFECTS

// hide all paragraphs.
//$("p").hide(4000);

//$("p").fadeOut(4000);

// EVENTS

// simple click
//$("#pageID").click(function() {
//   $("#pageID").text("You clicked me!");
//});

// add $(this) to refer to current element
//$("h2").click(function() {
//   $(this).text("You clicked me!");
//});

// add effects - this makes each paragraph fade out when clicked.
//$("p").click(function() {
//  $(this).fadeOut(2000);
//});

// Page load events - instead of window.onload()
//$(document).ready(function () {
//  $("#pageID").text("The DOM is fully loaded.");
//});

// you don't have to worry about accidentally calling it multiple times.
//$(document).ready(function () {
//   $("h1").css("color","red");
//});


JQuery Methods
----------------
jQuery("#myDiv").addClass("highlight");
                .removeClass("highlight");
        .toggleClass("highlight");

you can alias jQuery with $ sign
$("#myDiv").addClass("highlight");

Using a Content Distribution Network (CDN) for jQuery script link
-------------------------------------------------------------------
improved speed/redundancy
improved bandwidth
improved parallel downloads

Caching Benefits
------------------

Other javascript libraries
-----------------------------
code.google.com/api/libraries


Chapter 12 Javascript and HTML5
================================

HTML5 is a collection of features not one thing
video/audio support
geolocation
offline local storage
drag-and-drop
canvas element
New form elements

caniuse.com
-table for HTML5 support for different browsers


Javascript additions
---------------------
var c = document.getElementByClassName("first second");

HTML5 Video
-------------

Web workers
-------------

Feature Detection
-------------------

Modernizer.com
----------------
Javascript for HTML5
Put in head section of html

Using modernizr
-----------------
if (Modernizr.video) {
  // yes - use HTML5 video
} else {
  // perhaps replace with Flash video
}


Strict mode 
-------------------------------------
To put your code to be checked to high standards
put this line on the top of a javascript file "use strict";


Chapter 13 Advanced Javascript Features
========================================

Regular Expressions
--------------------

Create Regular Expressions
---------------------------
var myRE = /hello/;

//or 
var myRE = new RegExp("hello");

var myString = "Does this sentence have the word hello in it?";
if (myRE.test(myString)) {
    alert("Yes");
}

Creating Patterns
-----------------
var myRE = /^hello/;  // ^ at the start
       /hello$/;  // $ at the end
           /hel+o/;   // + once or more "helo", "hello", "hellllllo"
       /hel*o/;   // * zero or more  "heo", "helo", "hellllllo"
           /hel?o/;   // ? zero or more  "heo", "helo", "hello", "hellllllo"

Creating Patterns
------------------
/hello|goodbye/;  // either|or
/he..o/;      // . any character
/\wello/;         // \w character or _
/[crnld]ope/;     // [...] range of chars


More Complex Patterns
----------------------
/^[0-9]{5}<?:-[0-9]{4})?$/

email address regular expression
/^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$/

There are a lot of resources in the internet for regular expressions to search


What is AJAX
------------

1. Create the reqeust
2. Deal with any response

Create the request
-------------------
var myRequest;
//feature check!

if (window.XMLHttprequest) {  // Firefox, Safari
    myRequest = new XMLHttprequest();
} else if (window.ActiveXObject) {  // IE
    myRequest = new ActiveXObject("Microsoft.XMLHTTP");
}

// configure and send
myRequest.open("GET", "http://mysite.com/somedata.php", true);
myReqeust.send(null);

Prepare to accept the response
-------------------------------
myRequest.onreadystatechange = function(){
    console.log("We are called");
};

// THEN configure and send
myRequest.open("GET", "http://mysite.com/somedata.php", true);
myReqeust.send(null);

// Simple Ajax example.

// 1: Create the request 
var myRequest;

// feature check!
if (window.XMLHttpRequest) {  // does it exist? we're in Firefox, Safari etc.
    myRequest = new XMLHttpRequest();
} else if (window.ActiveXObject) { // if not, we're in IE
    myRequest = new ActiveXObject("Microsoft.XMLHTTP");
}

// 2: create an event handler for our request to call back
myRequest.onreadystatechange = function(){
    console.log("We were called!");
    console.log(myRequest.readyState);
    if (myRequest.readyState === 4) {
        var p = document.createElement("p");
        var t = document.createTextNode(myRequest.responseText);
        p.appendChild(t);
        document.getElementById("mainContent").appendChild(p);
    }
};

// open and send it
myRequest.open('GET', 'simple.txt', true);
// any parameters?
myRequest.send(null);

//....


Javascript to avoid
--------------------

document.write
---------------
document.write("Here is some <em>important</em> content");

document.write does not understand XHTML and DOM

better use innerHTML or manipulate individual DOM elements and text nodes


Browser sniffing
------------------
if (navigator.userAgent.indexOf('Netscape') ...
or
if(navigator.appName == 'Microsoft Internet Explorer')...


Eval function
---------------
var a = "alert('";
var b = "hello";
var c = "');";

eval(a + b + c);

eval function can be injected 

Pseudo-protocols
------------------
<p>Inside your HTML, you may find:
<a href="javascript:someFunction()">this</a>
</p>

<p>a preferable way is
<a href="nojavascript.html"
    onclick="someFunction(); return false;">this</a>
</p>

Introduction to Prototypes
---------------------------
var todaysDate = new Date();
var myArray = new Array();
var myRE = new RegExp("he..o);

var playerFred = { name: "Fred", score: 10000, rank:1 };

javascript prototype language
prototypejs.org

Creating objects
-----------------
//create an object
var playerFred = { name: "Fred", score: 10000, rank:1 };
//add a new property
playerFred.gameType = "MMORPG";
//add a method
playerFred.logScore = function() {
    console.log(this.score);
};

//call the method
playerFred.logScore();

//create another object
var playerBob = { name: "Bob", highscore: 50, level: "b" };

Formalizing objects with constructors
--------------------------------------
function Player() {
    this.name = n;    // this is the current object
}

var fred = new Player("Fred");
var bob = new Player("Bob");

// Simple prototype example

function Player(n,s,r) {
    this.name = n;
    this.score = s;
    this.rank = r;
}

Player.prototype.logInfo = function() {
    console.log("I am:" , this.name);
}

Player.prototype.promote = function() {
    this.rank++;
    console.log("My new rank is: " , this.rank);
}


var fred =  new Player("Fred",10000,5);
fred.logInfo();
fred.promote();

var bob = new Player("Bob",50,1);
bob.logInfo();
bob.promote();

var jane = new Player("Jane",50000,10);
jane.logInfo();
jane.promote();


Chapter 14 Putting it all together
===================================
index.html

<!doctype html>
<head>
  <title>Countdown</title>
  <style type="text/css">
   body {
        font-family: sans-serif;
        color: #333;
   }
   #container {
       width: 400px;
       margin: auto;
   }
   h1 { font-size: 5em; }
  </style>
</head>
<body>
  <div id="container">
      <div id="inputArea">
      </div>
      
      <h1 id="time">0:00</h1>
      
  </div> 
  <script src="script.js"></script>
</body>
</html>

script.js
// two global variables
var secondsRemaining;
var intervalHandle;

function resetPage() {
    document.getElementById("inputArea").style.display = "block";
}

function tick() {
    // grab the h1
    var timeDisplay = document.getElementById("time");
    
    // turn seconds into mm:ss
    var min = Math.floor(secondsRemaining / 60);
    var sec = secondsRemaining - (min * 60);
    
    // add a leading zero (as a string value) if seconds less than 10
    if (sec < 10) {
        sec = "0" + sec;
    }
    // concatenate with colon
    var message = min + ":" + sec;
    // now change the display
    timeDisplay.innerHTML = message;
    
    // stop if down to zero
    if (secondsRemaining === 0) {
        alert("Done!");
        clearInterval(intervalHandle);
        resetPage();
    }
    // subtract from seconds remaining
    secondsRemaining--;
}

function startCountdown() {
    // get contents of the "minutes" text box
    var minutes = document.getElementById("minutes").value;
    // check if not a number
    if (isNaN(minutes)) {
        alert("Please enter a number!");
        return;
    }
    // how many seconds?
    secondsRemaining =  minutes * 60;
    // every second, call the "tick" function
    intervalHandle = setInterval(tick, 1000);
    // hide the form
    document.getElementById("inputArea").style.display = "none";
}

// as soon as the page is loaded...
window.onload =  function () {
    // create input text box and give it an id of "minutes"
    var inputMinutes = document.createElement("input");
    inputMinutes.setAttribute("id", "minutes");
    inputMinutes.setAttribute("type", "text");
    // create a button
    var startButton = document.createElement("input");
    startButton.setAttribute("type", "button");
    startButton.setAttribute("value", "Start Countdown");
    startButton.onclick = function () {
        startCountdown();
    };
    // add to the DOM, to the div called "inputArea"
    document.getElementById("inputArea").appendChild(inputMinutes);
    document.getElementById("inputArea").appendChild(startButton);
};

function adjustStyle() {
    var width = 0;
    // get the width.. more cross-browser issues
    if (window.innerHeight) {
        width = window.innerWidth;
    } else if (document.documentElement && document.documentElement.clientHeight) {
        width = document.documentElement.clientWidth;
    } else if (document.body) {
        width = document.body.clientWidth;
    }
    // now we should have it
    if (width < 600) {
        document.getElementById("myCSS").setAttribute("href", "_css/narrow.css");
    } else {
        document.getElementById("myCSS").setAttribute("href", "_css/main.css");
    }
}

// now call it when the window is resized.
window.onresize = function () {
    adjustStyle()
};


Third-party libraries
-----------------------
jqueryui.com

google cdn

main.html

<div id="accordion">

<h3><a href="#">Customer notifications</a></h3>
<div>
<p>When you book a tour with Explore California, you should receive two notifications via email. The first will be a <strong>tour confirmation</strong>, which states that your tour is booked, gives you the dates of your tour, and lists all amenities included in your package. The second notification should arrive two weeks prior to the start of your tour. This will be a <strong>reminder notification</strong> and will contain your tour dates and current tour conditions, if applicable. <em>If you do not receive a confirmation within 24 hours, or the reminder notification two weeks out, contact us immediately</em>. We’ll make sure there are no problems in the system and confirm your tour.</p>
</div>
<h3><a href="#">Tour vouchers</a></h3>
<div>
<p>Some tour packages include tour vouchers. These tour vouchers allow you to participate in optional activities during a tour and are usually scheduled for downtime or as an optional choice to replace the day’s featured activity. The vouchers are only good during the tour and have no cash value, and cannot be redeemed if the tour is not taken. The tour vouchers are negotiated with 3rd party vendors. Although Explore California monitors these vendors closely, we cannot guarantee that scheduled activities will take place.</p>
</div>
<h3><a href="#">Trip planning</a></h3>
<div>
<p>After registration, you will be sent a PDF trip planning document specific to your tour. In the Trip Planner we offer packing advice, places of interest along the tour route, a historical and environmental overview of the tour, a list of any required equipment for the tour that is <em>not</em> provided by Explore California, and additional resources for researching the surrounding area and points of interest included in your tour. Additional information about specific tours can be found in our FAQ section.</p>
</div>
<h3><a href="#">Tour checklist</a></h3>
<div>
<p>As you prepare for your tour, we want to make sure that you have everything you need to fully enjoy your time in California. Having everything in place when you arrive makes it easy to sit back and enjoy all that your tour has to offer. With that in mind, we’ve prepared a small checklist to help you make sure you’re ready to go!</p>
<ul>
  <li>Have you arranged for your mail/paper deliver?</li>
  <li>Are friends/family aware of your itinerary?</li>
</ul>
</div>

</div>
<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.6.1/jquery.min.js"></script>
<script src="https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.13/jquery-ui.min.js"></script>
<script src="script.js"></script>
</body>
</html>

script.js
window.onload = function () {
   $("#accordion").accordion();
};


Chapter 15 Conclusion
=======================
https://developer.mozilla.org/en-US/
dev.opera.com
jquery.com
http://developer.yahoo.com/javascript/
http://developer.yahoo.com/performance
stackoverflow.com
linda.com


Introduction
Syntax
How to think about it, write it
Debug it
Work with DOM
Best practices
Work with functions
Libraries

Its like learning playing a music instrument but to get use you have to put your hands on it.


