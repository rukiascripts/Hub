local stringPattern = "%s(.)";
return function (text)
	return string.lower(text):gsub(stringPattern, string.upper);
end;