-- HR Analytics Employee Attrition & Performance
-- Skills used: Joins, CTE's, Temp Tables, Windows Functions, Aggregate Functions, Creating Views, Converting Data Types, Dynamic Procedures


--- 1.-PERFORMANCE ANALYSIS

---- Is there any correlation between EnvironmentSatisfaction, JobSatisfaction, RelationshipSatisfaction, Self-Rating and Manager-Rating?
GO
IF (OBJECT_ID('dbo.CalculatePearsonCorrelation', 'P') IS NOT NULL) BEGIN
  DROP PROCEDURE dbo.CalculatePearsonCorrelation;
END;

GO
CREATE PROCEDURE CalculatePearsonCorrelation
    @columnX NVARCHAR(50),
    @columnY NVARCHAR(50),
    @tableName NVARCHAR(50)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @correlationResult FLOAT;

    SET @sql = '
    SELECT 
        @correlationResult = 
        (COUNT(*) * SUM(' + @columnX + ' * ' + @columnY + ') - SUM(' + @columnX + ') * SUM(' + @columnY + ')) /
        (SQRT(COUNT(*) * SUM(' + @columnX + ' * ' + @columnX + ') - POWER(SUM(' + @columnX + '), 2)) *
         SQRT(COUNT(*) * SUM(' + @columnY + ' * ' + @columnY + ') - POWER(SUM(' + @columnY + '), 2)))
    FROM ' + @tableName;

    EXEC sp_executesql @sql, N'@correlationResult FLOAT OUTPUT', @correlationResult OUTPUT;

    SELECT @correlationResult AS PearsonCorrelation;
END;

-- Environment Satisfaction - ManagerRating -> Output -0.006
EXEC CalculatePearsonCorrelation 'EnvironmentSatisfaction', 'ManagerRating', '[HR Analytics].dbo.PerformanceRating' ;
-- Job Satisfaction - ManagerRating -> Output -0.016
EXEC CalculatePearsonCorrelation 'JobSatisfaction', 'ManagerRating', '[HR Analytics].dbo.PerformanceRating' ;
-- Relationships Satisfaction - ManagerRating -> Output 0.019
EXEC CalculatePearsonCorrelation 'RelationshipSatisfaction', 'ManagerRating', '[HR Analytics].dbo.PerformanceRating' ;
-- SelfRating - ManagerRating -> Output 0.85
EXEC CalculatePearsonCorrelation 'SelfRating','ManagerRating', '[HR Analytics].dbo.PerformanceRating' ;
-- We can conclude that neither environment satisfaction, job satisfaction or relationship satisfaction has a meaningful impact on how a manager rate his employees. This could mean that there are another factors
-- that are not being taken into consideration.
-- There is a strong positive correlation between self rating and manager rating, meaning that both employee and manager rate the employee performance similarly


---- What is the average manager rating per department, and how does it compare with self-ratings?
SELECT Employee.Department, ROUND(AVG(CAST(Rating.ManagerRating AS FLOAT)),2) AS avg_manager_rating, ROUND(AVG(CAST(Rating.SelfRating AS FLOAT)),2) AS avg_self_rating
FROM [HR Analytics].dbo.Employee AS Employee
JOIN [HR Analytics].dbo.PerformanceRating  AS Rating
	ON Employee.EmployeeID = Rating.EmployeeID
GROUP BY Employee.Department
-- All departments have a similar rating on average, being the Technology department the highest rated. We can conclude that on average employees tend to rate themselves higher than the rate managers give them.


--- 2.-EMPLOYEE RETENTION AND ATTRITION

---- What is the relationship between employee satisfaction (environment, job, relationship) and attrition?
SELECT Employee.Attrition, 
	ROUND(AVG(CAST(Rating.EnvironmentSatisfaction AS FLOAT)),2) AS avg_environment_satisfaction, 
	ROUND(AVG(CAST(Rating.JobSatisfaction AS FLOAT)),2) AS avg_job_satisfaction,
	ROUND(AVG(CAST(Rating.RelationshipSatisfaction AS FLOAT)),2) AS avg_relationship_satisfaction
FROM [HR Analytics].dbo.Employee AS Employee
JOIN [HR Analytics].dbo.PerformanceRating  AS Rating
	ON Employee.EmployeeID = Rating.EmployeeID
GROUP BY Employee.Attrition
-- There is no significative difference in satisfaction between groups who left the company and those who not. Employees who left the company even score slightly higher on average.

-- Does job satisfaction change over time, and how does that relate to attrition?

GO
WITH SatisfactionTrends AS (
    SELECT 
        p.EmployeeID,
        p.ReviewDate,
        p.JobSatisfaction,
        e.Attrition,
        LEAD(CAST(p.JobSatisfaction AS INT)) OVER (PARTITION BY p.EmployeeID ORDER BY p.ReviewDate) AS NextJobSatisfaction,
        (LEAD(CAST(p.JobSatisfaction AS INT)) OVER (PARTITION BY p.EmployeeID ORDER BY p.ReviewDate) - CAST(p.JobSatisfaction AS INT)) AS SatisfactionChange
    FROM [HR Analytics].dbo.PerformanceRating p
    JOIN [HR Analytics].dbo.Employee e
        ON p.EmployeeID = e.EmployeeID
), averageSatisfactionChange AS(
SELECT 
    EmployeeID, 
    ROUND(AVG(CAST(SatisfactionChange AS FLOAT)),2) AS AvgSatisfactionChange, 
    Attrition
FROM SatisfactionTrends
GROUP BY EmployeeID, Attrition
)
SELECT Attrition,
	SUM(AvgSatisfactionChange) AS TotalSatisfactionChange
FROM averageSatisfactionChange
GROUP BY Attrition
--People leaving the company has on average a negative job satisfaction evolution

----Does the distance from home impact employee attrition?
SELECT 
    Attrition,
    ROUND(AVG(CAST(DistanceFromHome_KM AS FLOAT)),2) AS AvgDistance,
    ROUND(MIN(CAST(DistanceFromHome_KM AS FLOAT)),2) AS MinDistance,
    ROUND(MAX(CAST(DistanceFromHome_KM AS FLOAT)),2) AS MaxDistance,
    COUNT(*) AS EmployeeCount
FROM 
    [HR Analytics].dbo.Employee AS Employee
GROUP BY 
    Attrition;
-- There is no significative difference in distance either.

---- Does the years at company impact employee attrition??
SELECT Attrition, 
	ROUND(AVG(CAST(YearsAtCompany AS FLOAT)),2) AS AvgYearsAtCompany,
    ROUND(MIN(CAST(YearsAtCompany AS FLOAT)),2) AS MinYearsAtCompany,
    ROUND(MAX(CAST(YearsAtCompany AS FLOAT)),2) AS MaxYearsAtCompany, 
	ROUND(AVG(CAST(YearsInMostRecentRole AS FLOAT)),2) AS AvgYearsInMostRecentRole,
    ROUND(MIN(CAST(YearsInMostRecentRole AS FLOAT)),2) AS MinYearsInMostRecentRole,
    ROUND(MAX(CAST(YearsInMostRecentRole AS FLOAT)),2) AS MaxYearsInMostRecentRole,
	COUNT(*) AS EmployeeAmount
FROM [HR Analytics].dbo.Employee
GROUP BY 
	Attrition;
--Let's see the year distribution

WITH AttEmployee AS (
	SELECT *
	FROM [HR Analytics].dbo.Employee
	WHERE Attrition = 1)
SELECT YearsAtCompany, COUNT(*) AS EmployeeAmount
FROM AttEmployee
GROUP BY YearsAtCompany
-- This shows that the first 2 years play a relevant role in Employee retention. 


---- Is there a trend in attrition based on the number of training opportunities taken?
SELECT 
	performance.TrainingOpportunitiesTaken, 
	COUNT(CASE WHEN employee.Attrition = 1 THEN 1 END) as AttritionCount,
	COUNT(CASE WHEN employee.Attrition = 0 THEN 1 END) as NoAttritionCount, 
	COUNT(*) as TotalEmployees,
	(COUNT(CASE WHEN employee.Attrition = 1 THEN 1 END) * 1.0 / COUNT(*)) * 100 AS AttritionRate
FROM [HR Analytics].dbo.PerformanceRating as performance
JOIN [HR Analytics].dbo.Employee as employee
	ON performance.EmployeeID = employee.EmployeeID
GROUP BY TrainingOpportunitiesTaken
ORDER BY 
    performance.TrainingOpportunitiesTaken;
-- For employees who take 3 training opportunities, the attrition rate drops significantly, suggesting that employees with more training opportunities are 
-- less likely to leave compared to those with fewer training opportunities. It is possible that providing more training opportunities (3 or more) helps employees develop their skills,
-- stay motivated, and feel more invested in the company, leading to lower attrition.

---- Are employees less engeaged with training than previous years when they leave the company?
WITH EmployeeFinalYear AS(
	-- Find the final review date for employees who left the company
	SELECT 
		performance.EmployeeID,
		MAX(performance.ReviewDate) AS finalReviewDate
	FROM [HR Analytics].dbo.PerformanceRating AS performance
	JOIN [HR Analytics].dbo.Employee AS employee
		ON performance.EmployeeID = employee.EmployeeID
	WHERE employee.Attrition = 1
	GROUP BY performance.EmployeeID
),
TrainingEngagement AS (
	-- Compare training engagement between the final year and previous years
    SELECT 
        performance.EmployeeID, 
        performance.ReviewDate, 
        performance.TrainingOpportunitiesTaken,
		performance.TrainingOpportunitiesWithinYear,
		CASE 
			WHEN performance.ReviewDate = finalYear.finalReviewDate THEN 'Final Year'
			ELSE 'Previous Year'
		END AS ReviewPeriod,
		-- Calculate the ratio of training taken to available opportunities
        (CAST(performance.TrainingOpportunitiesTaken AS FLOAT) / 
         CAST(performance.TrainingOpportunitiesWithinYear AS FLOAT)) AS TrainingTakenRatio,
        -- Calculate the difference between opportunities available and taken
       (CAST(performance.TrainingOpportunitiesWithinYear AS INT) - CAST(performance.TrainingOpportunitiesTaken AS INT)) AS MissedOpportunities

    FROM [HR Analytics].dbo.PerformanceRating AS performance
	JOIN EmployeeFinalYear as finalYear
		ON performance.EmployeeID = finalYear.EmployeeID
)
SELECT 
    ReviewPeriod, 
    AVG(CAST(TrainingOpportunitiesTaken AS FLOAT)) AS AvgTrainingOpportunitiesTaken,
    AVG(CAST(TrainingOpportunitiesWithinYear  AS FLOAT)) AS AvgTrainingOpportunitiesAvailable,
    AVG(TrainingTakenRatio) AS AvgTrainingTakenRatio,
    AVG(CAST(MissedOpportunities  AS FLOAT)) AS AvgMissedOpportunities
FROM 
    TrainingEngagement
GROUP BY 
    ReviewPeriod;
-- AvgTrainingOpportunitiesAvailable is constant but AvgTrainingOpportunitiesTaken decreases in the final year. 
-- It suggests that employees had the same training opportunities available but chose not to engage with them before leaving.
-- AvgTrainingTakenRatio drops significantly in the final year, this may indicate that disengagement with training is a precursor to attrition.
-- MissedOpportunities is higher in the final year. Employees may have had opportunities to engage but opted not to, which could indicate a decline in motivation or satisfaction before they decided to leave.


--- 3.- Training and Development

---- Are employees who take more training opportunities rated higher by managers?
SELECT TrainingOpportunitiesTaken,
	AVG(CAST(ManagerRating AS FLOAT)) AS AvgManagerRating,
	COUNT(*) AS EmployeeCount
FROM [HR Analytics].dbo.PerformanceRating 
GROUP BY TrainingOpportunitiesTaken
ORDER BY TrainingOpportunitiesTaken
-- AvgManagerRating increases slightly with more training opportunities taken, it may suggests that employees who take 
-- more training tend to receive higher performance ratings from their managers.

---- What is the distribution of training opportunities within different departments?
SELECT employee.Department,
	ROUND(AVG(CAST(performance.TrainingOpportunitiesTaken AS FLOAT)),2) AS AVGTrainingOpportunitiesTaken,
	SUM(performance.TrainingOpportunitiesTaken) AS TotalTrainingOpportunitiesTaken,
	COUNT(performance.EmployeeID) AS EmployeeCount
FROM [HR Analytics].dbo.PerformanceRating AS performance
JOIN [HR Analytics].dbo.Employee AS employee
	ON performance.EmployeeID = employee.EmployeeID
GROUP BY
	employee.Department
ORDER BY
	AVGTrainingOpportunitiesTaken
--There are no significative differences between departments


--- 4.- Work-Life Balance

---- What is the average work-life balance rating across different departments, and how does it relate to overtime?
SELECT employee.Department,
	employee.OverTime,
	ROUND(AVG(CAST(performance.WorkLifeBalance AS FLOAT)),2) AS AVGWorkLifeBalance,
	COUNT(performance.EmployeeID) AS EmployeeCount 
FROM [HR Analytics].dbo.PerformanceRating AS performance
JOIN [HR Analytics].dbo.Employee AS employee
	ON performance.EmployeeID = employee.EmployeeID
GROUP BY
	employee.Department, employee.OverTime
ORDER BY Department, employee.OverTime
-- Employees doing overtime hours tend to rate their Work-life balance lower on average than employees who don't. It is significatively prominent in the Human resources department

---- Does work-life balance impact attrition?
SELECT 
    employee.Attrition, 
    ROUND(AVG(CAST(performance.WorkLifeBalance AS FLOAT)),2) AS AVGWorkLifeBalance,
    COUNT(employee.EmployeeID) AS EmployeeCount
FROM 
    [HR Analytics].dbo.PerformanceRating AS performance
JOIN 
    [HR Analytics].dbo.Employee AS employee
    ON performance.EmployeeID = employee.EmployeeID
GROUP BY 
    employee.Attrition
ORDER BY 
    employee.Attrition;
-- WorkLifeBalance has no significative impact on Attrition.


--- 5.- Demographic Analysis

---- How do performance ratings vary by demographic factors such as gender, age, and ethnicity?
--Full Picture into temp table
IF (OBJECT_ID('tempdb..#demographics') IS NOT NULL) 
BEGIN
    DROP TABLE #demographics;
END

CREATE TABLE #demographics(
	EmployeeID VARCHAR(50),
    Gender VARCHAR(50),
    Ethnicity VARCHAR(50),
    AgeGroup VARCHAR(10),
	SelfRating INT,
	ManagerRating INT
);
INSERT INTO #demographics
SELECT 
	performance.EmployeeID,
    Gender,
    Ethnicity,
    CASE 
        WHEN employee.Age BETWEEN 18 AND 29 THEN '18-29'
        WHEN employee.Age BETWEEN 30 AND 39 THEN '30-39'
        WHEN employee.Age BETWEEN 40 AND 49 THEN '40-49'
        WHEN employee.Age BETWEEN 50 AND 59 THEN '50-59'
        ELSE '60+'
    END AS AgeGroup,
    performance.SelfRating,
	performance.ManagerRating
FROM 
    [HR Analytics].dbo.PerformanceRating AS performance
JOIN 
    [HR Analytics].dbo.Employee AS employee
    ON performance.EmployeeID = employee.EmployeeID

--Gender distrubution
SELECT Gender,
	ROUND(AVG(CAST(SelfRating AS FLOAT)),2) AS AvgSelfRating,
    ROUND(AVG(CAST(ManagerRating AS FLOAT)),2)  AS AvgManagerRating,
    COUNT(EmployeeID) AS EmployeeCount
FROM #demographics
GROUP BY Gender
ORDER BY AvgManagerRating
-- Female, Male and Non-Binary have a similar Manager rating being the female gender the best rated. "Prefer Not To Say" group fall apart but since employees who selected "Prefer Not To Say" are 
--a much smaller group, the lower manager ratings could be due to limited sample size or other factors like their roles within the company.

--Age distrubution
SELECT AgeGroup,
	ROUND(AVG(CAST(SelfRating AS FLOAT)),2) AS AvgSelfRating,
    ROUND(AVG(CAST(ManagerRating AS FLOAT)),2)  AS AvgManagerRating,
    COUNT(EmployeeID) AS EmployeeCount
FROM #demographics
GROUP BY AgeGroup
ORDER BY AgeGroup
-- Manager ratings are relatively consistent for all age groups, ranging from 3.46 to 3.50. However, employees in the 50-59 age group receive a much lower average manager rating of 2.83. 
--This again may be due to the very small sample size.

--Ethnicity distrubution
SELECT Ethnicity,
	ROUND(AVG(CAST(SelfRating AS FLOAT)),2) AS AvgSelfRating,
    ROUND(AVG(CAST(ManagerRating AS FLOAT)),2)  AS AvgManagerRating,
    COUNT(EmployeeID) AS EmployeeCount
FROM #demographics
GROUP BY Ethnicity
ORDER BY AvgManagerRating
--Native Hawaiian have the lower average manager rating while Asians employees who identify as other ethnicities score the highest

---- Is there a pay disparity across different ethnicities and genders?
SELECT Ethnicity,
	ROUND(AVG(CAST(Salary AS FLOAT)),2)  AS AvgSalary,
	Count(*) AS Total
FROM [HR Analytics].dbo.Employee
GROUP BY Ethnicity
ORDER BY AvgSalary
-- There is indeed a disparity in pay across different ethnicities which is odd knowing that it doesn't correlate with manager rating. This could have multiple causes such as Age/Location/Department that
--requires further analysis

SELECT Gender,
	ROUND(AVG(CAST(Salary AS FLOAT)),2)  AS AvgSalary,
	Count(*) AS Total
FROM [HR Analytics].dbo.Employee
GROUP BY Gender
ORDER BY AvgSalary
-- Employees who prefer no to say have a bigger salary than others. This again may be due to the very small sample size. Non-Binary and male employees are paid a very similar amount on average and female 
-- workers have a sensitive bigger salary.


--- 6.- Promotions and Career Growth

---- How does the frequency of promotions relate to tenure?
GO
IF (OBJECT_ID('PromotionFrequency','v') IS NOT NULL) 
BEGIN
    DROP VIEW PromotionFrequency;
END
GO
CREATE VIEW PromotionFrequency AS
SELECT 
    e.EmployeeID,
    e.FirstName,
    e.LastName,
    e.YearsAtCompany,
    e.YearsSinceLastPromotion,
	CASE
		WHEN e.YearsSinceLastPromotion = e.YearsAtCompany THEN 0
		ELSE COUNT(*) OVER (PARTITION BY e.EmployeeID) 
	END AS TotalPromotions,
    CASE 
        WHEN e.YearsSinceLastPromotion < 1 THEN 'Recent Promotion'
        WHEN e.YearsSinceLastPromotion BETWEEN 1 AND 3 THEN 'Moderate'
        ELSE 'Long Time Since Promotion'
    END AS PromotionCategory
FROM [HR Analytics].dbo.Employee e;
GO

SELECT * 
FROM PromotionFrequency

---- Is there a relationship between years since last promotion and job satisfaction?
IF (OBJECT_ID('tempdb..#yearsAndJob') IS NOT NULL) 
BEGIN
    DROP TABLE #yearsAndJob;
END
CREATE TABLE #yearsAndJob(
	YearsSincePromotion INT,
    AVGJobSatisfaction FLOAT
)
INSERT INTO #yearsAndJob
SELECT employee.YearsSinceLastPromotion,
	ROUND(AVG(CAST(performance.JobSatisfaction AS FLOAT)),2) AS avgJobSatisfaction
FROM [HR Analytics].dbo.Employee AS employee
JOIN [HR Analytics].dbo.PerformanceRating AS performance
	ON employee.EmployeeID = performance.EmployeeID
GROUP BY  employee.YearsSinceLastPromotion
ORDER BY employee.YearsSinceLastPromotion

EXEC CalculatePearsonCorrelation 'YearsSincePromotion','AVGJobSatisfaction', 'tempdb..#yearsAndJob' ;
-- There is a weak to none relationship (r = 0.215) between years since last promotions and job satisfaction


--- 7.- Departmental Performance

---- Which department has the highest average performance rating, and how does it correlate with employee satisfaction and training opportunities?
SELECT Department,
	ROUND(AVG(CAST(performance.ManagerRating AS FLOAT)),2) AS avgManagerRating, 
	ROUND(AVG(CAST(performance.EnvironmentSatisfaction AS FLOAT)),2) AS avgEnvironmentSatisfaction,
	ROUND(AVG(CAST(performance.JobSatisfaction AS FLOAT)),2) AS avgJobSatisfaction,
	ROUND(AVG(CAST(performance.RelationshipSatisfaction AS FLOAT)),2) AS avgRelationshipSatisfaction
FROM [HR Analytics].dbo.Employee AS employee
JOIN [HR Analytics].dbo.PerformanceRating AS performance
	ON employee.EmployeeID = performance.EmployeeID
GROUP BY Department
ORDER BY avgManagerRating

---- What is the distribution of salary and tenure across departments?
GO
IF (OBJECT_ID('SalaryTenureDepartment','v') IS NOT NULL)
BEGIN
    DROP VIEW SalaryTenureDepartment;
END

GO
CREATE VIEW SalaryTenureDepartment AS
SELECT 
    e.Department,
    e.EmployeeID,
    e.Salary,
    e.YearsAtCompany,
    RANK() OVER (PARTITION BY e.Department ORDER BY e.Salary DESC) AS SalaryRank,
    DENSE_RANK() OVER (PARTITION BY e.Department ORDER BY e.YearsAtCompany DESC) AS TenureRank
FROM [HR Analytics].dbo.Employee e;

GO
SELECT *
FROM SalaryTenureDepartment
--- 8.- Business Travel Impact

---- What is the impact of business travel on employee retention?
SELECT 
    e.BusinessTravel,
    COUNT(e.EmployeeID) AS TotalEmployees,
    SUM (CAST(Attrition AS INT)) AS AttritionCount,
    ROUND((CAST(SUM (CAST(Attrition AS INT)) AS FLOAT) / COUNT(e.EmployeeID)) * 100, 2) AS AttritionRate
FROM [HR Analytics].dbo.Employee e
GROUP BY e.BusinessTravel;
-- This clearly shows that the frequency of business travels has a negative impact on employee retention

---- How does business travel frequency correlate with performance ratings?
SELECT employee.BusinessTravel,
	ROUND(AVG(CAST(performance.ManagerRating AS FLOAT)),2) AS avgManagerRating,
	COUNT(employee.EmployeeID)
FROM [HR Analytics].dbo.Employee AS employee
JOIN [HR Analytics].dbo.PerformanceRating AS performance
	ON employee.EmployeeID = performance.EmployeeID
GROUP BY employee.BusinessTravel
-- Employees that don't travel have a better manager rating on average that employees that do.
