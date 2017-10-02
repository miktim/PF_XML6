CREATE OR REPLACE PACKAGE  "PF_XML6" as
/*
 Пакет анализа/генерации обменных XML-файлов ПФР 2011-2016гг
 (с)2014-2017 miktim@mail.ru, Петрозаводский государственный университет, РЦНИТ 
 Использование пакета регулируется лицензией MIT 
*/ 
c_program constant varchar2(256):='PF_XML6';
c_version constant varchar2(10):='70200'; -- 
period_error EXCEPTION; -- ошибка данных периода 
pragma exception_init(period_error,-20201); 
org_error EXCEPTION;    -- ошибка данных организации 
pragma exception_init(org_error,-20202); 
form_error EXCEPTION;   -- ошибка данных формы 
pragma exception_init(form_error,-20203); 
unsupported EXCEPTION;  -- не поддерживаемые данные 
pragma exception_init(unsupported,-20204); 
-- Номер (вид) формы 
subType fn_tp is char(1); 
fn_szv1 constant fn_tp := 1; -- СЗВ-6-1 (2010-2012) 
fn_szv2 constant fn_tp := 2; -- СЗВ-6-2 (2010-2012, СЗВ-6-1 без льготных периодов) 
fn_szv3 constant fn_tp := 3; -- СЗВ-6-3 (2011-2012, не упоминается с 2014г) 
fn_szv4 constant fn_tp := 4; -- СЗВ-6-4 (2013) 
fn_szvr constant fn_tp := 5; -- СЗВ-РСВ (2014-2016 РСВ-1 6й раздел) 
/*
fn_szvs constant fn_tp := 6; -- СЗВ-СТАЖ (2017 - )
fn_szvc constant fn_tp := 7; -- СЗВ-КОРР (2017 - )
*/
-- 
fn_adv constant fn_tp := 8;  -- АДВ опись пачек форма (распознается, но не парсится!) 
fn_rsv constant fn_tp := 9;  -- РСВ расчетная форма 
-- 
subType money_tp is number(15,2); 
subType emptype_tp is varchar2(5 char); -- код категории застрахованного лица 
-- ORG Плательщик 
Type org_tp is record 
( ONAME varchar2(50 char) -- краткое наименование организации 
, OPFN number(12)     -- регистрационный номер организации в ПФР 
, OINN number(12)     -- ИНН организации 
, OKPP number(9)      -- КПП организации 
, OKVED varchar2(16 char) -- ОКВЭД организации
, PCODE char(2)       -- код периода
, PINDEX number(1)    -- индекс отчетного квартала (1-4) 
, PYEAR number(4)     -- отчетный год 
, SDECK number(5):=1  -- стартовый номер пачек    
); 
-- HDR Заголовок формы (СЗВ-6-1,2,3,4, СЗВ-РСВ), таблица форм 
Type hdr_tp is record 
( FID number           -- индекс формы 
--, EXTFID varchar2(128)  -- внешний ID формы 
, FN fn_tp             -- номер (вид) формы 
, LNAME varchar2(40 char)   -- фамилия 
, FNAME varchar2(40 char)   -- имя 
, SNAME varchar2(40 char)   -- отчество 
, SNILS number(11)     -- страховой номер индивидуального лицевого счета (СНИЛС) 
, FIRED char(1):=0     -- =1 : уволен (cо IIкв 2015г) 
, FTYPE varchar2(3 char)    -- тип сведений: ИСХ, КОР, ОТМ 
, CPCODE char(2)       -- код отчетного периода
, CPINDEX number(1)    -- ???индекс корректируемого квартала (1-4 квартал) 
, CPYEAR number(4)     -- корректируемый год (2010-?) 
, COPFN number(12)     -- регистрационный номер организации в ПФР в корректируемый период 
--, ADDRI varchar2(256)  -- адрес для информирования(отменен с 2013г) 
, EMPTYPE emptype_tp   -- код категории плательщика: НР, ВЖНР, ООИ, ... 
, CONTYPE varchar2(3 char)  -- тип договора: ТРУ-ТРУДОВОЙ, ГРА-ГРАЖДАНСКО-ПРАВОВОЙ 
, ISUM money_tp        -- страховая часть взносов или ОПС 2014г (начислено) 
, FSUM money_tp        -- накопительная часть взносов (начислено) 
, CISUM money_tp       -- страховая часть взносов или ОПС 2014г из корректируемой (уплачено) 
, CFSUM money_tp       -- накопительная часть взносов из корректируемой формы (уплачено) 
, XID number(5)        -- номер xml-файла в пачке 
/*
-- персональные данные для ФНС [0]
, INN number(12)       -- ИНН
, BDATE date           -- дата рождения
, COUNTRY char(3) := '643' -- гражданство (код страны: 643 - Россия)
, SEX char(1)          -- пол (1-мужской, 2-женский)
, DOCT char(2) := '21' -- код вида документа (21 - паспорт гражданина России)
, DOCSN varchar2(20 char)  -- серия/номер документа
, INSP char(3) := '111'    -- признаки страхования
--                     (пенсионного/медицинского/социального)
*/
); 
Type hdr_tbl_tp is table of hdr_tp; 
-- Записи о периодах работы [1,2,4,5] 
Type pd_tp is record 
( FID number         -- индекс формы 
, NN number(2)       -- порядковый номер записи 1-99 
, SDATE date         -- дата начала периода 
, EDATE date         -- дата окончания  
, TERR  varchar2(4 char)  -- территориальные условия: МКС, РКС, ... 
, TERRC number(4,2)  -- территориальный коэффициент (доля ставки ТУ) 
, DD varchar2(20)    -- декрет/дети 
, SPECS varchar2(128)-- строка прочих особенностей учета, разделенных ':' или null 
); 
Type pd_tbl_tp is table of pd_tp; 
-- Записи о доходах, облагаемых базах [3,4,5] 
Type inc_tp is record 
( FID number       -- индекс формы 
, PMON number(2)   -- месяц 1-12 (0 - сумма нарастающим итогом с начала года) 
, EMPTYPE emptype_tp -- категория застрахованного лица: НР, ВЖНР, ООИ, ... 
, SUMT money_tp    -- сумма выплат 
, SUMB money_tp    -- облагаемая база 
, SUMBG money_tp   -- … в т.ч. по ГПД 
, SUMO money_tp    -- сумма превышения 
); 
Type inc_tbl_tp is table of inc_tp; 
-- Записи о дополнительных выплатах [4,5] 
Type pmt_tp is record 
( FID number         -- индекс формы 
, PMON number(2)     -- месяц 1-12 (0 - сумма нарастающим итогом с начала года) 
, ACODE varchar2(10) -- код специальной оценки труда 
, SUMA1 money_tp     -- сумма выплат пп1... 
, SUMA2 money_tp     -- ... пп2... 
); 
Type pmt_tbl_tp is table of pmt_tp; 
-- Сведения о корректировках [5] 
Type cor_tp is record 
( FID number         -- индекс формы 
, CPINDEX number(1)  -- индекс корректируемого периода 
, CPYEAR number(4)   -- корректируемый год (null или 0 итого) 
, DPSUM money_tp     -- сумма доначисленных взносов ОПС 
, DISUM money_tp     -- ... страховая часть 
, DFSUM money_tp     -- ... накопительная часть 
); 
Type cor_tbl_tp is table of cor_tp; 
-- Структура формы 
Type form_tp is record  
( hdr hdr_tp         -- заголовок формы 
, periods pd_tbl_tp := pd_tbl_tp()   -- таблица записей о стаже (периодах работы) 
, incomes inc_tbl_tp := inc_tbl_tp() -- таблица записей о доходах/базах 
, payments pmt_tbl_tp := pmt_tbl_tp()-- таблица записей о дополнительных выплатах 
, corrs cor_tbl_tp := cor_tbl_tp()   -- сведения о корректировках 
); 
-- XML  Пачка форм (файл) : 
Type xml_tp is record 
( XID number(5)        -- номер файла в пачке 
, XFCOUNT number(3):=0 -- количество форм в файле 1-200 
, XKEY varchar2(32)    --*** ключ группировки форм = FN:FTYPE:CPINDEX:CPYEAR:CONTYPE:EMPTYPE 
                       -- '5:ИСХ::::' = СЗВ-РСВ, ИСХОДНАЯ, отчетный период в org 
, FN fn_tp             -- вид (номер) формы  
, FTYPE varchar2(3 char)    -- тип сведений: ИСХ, КОР, ОТМ 
, CPINDEX number(1)    -- индекс (квартал) корректируемого периода (1-4) 
, CPYEAR number(4)     -- корректируемый год (2010-2014) 
, EMPTYPE emptype_tp   -- код категории плательщика: НР, ВЖНР, ООИ, ... 
, CONTYPE varchar2(3 char)  -- тип договора:  
--                     'ТРУ'-ТРУДОВОЙ, 'ГРА'-ГРАЖДАНСКО-ПРАВОВОЙ 
); 
Type xml_tbl_tp is table of xml_tp; 
-- XML Информация о файле 
Type xml_info_tp is record 
( XNAME varchar2(256)  -- имя файла 
, XPROGRAM varchar2(40 char)-- программа 
, XVERSION varchar2(10 char)-- версия 
, ORG org_tp           -- организация и отчетный период 
, XFILE xml_tp         -- опись файла 
); 
-- Инициализация 
Procedure init(p_org org_tp); 
Procedure init; 
-- Сведения об организации и отчетном периоде 
Procedure org_set(p_org org_tp); 
Function org_get return org_tp; 
-- Управление формами 
Procedure form_clear(p_frm in out nocopy form_tp); 
Procedure form_add(p_frm in out nocopy form_tp); 
Procedure form_delete(p_fid number); 
Function form_get(p_fid number) return form_tp; 
Function forms_tbl return hdr_tbl_tp pipelined parallel_enable; 
Function periods_tbl(p_fid number:=null) return pd_tbl_tp pipelined parallel_enable; 
Function incomes_tbl(p_fid number:=null) return inc_tbl_tp pipelined parallel_enable; 
Function payments_tbl(p_fid number:=null) return pmt_tbl_tp pipelined parallel_enable; 
Function corrs_tbl(p_fid number:=null) return cor_tbl_tp pipelined parallel_enable; 
-- Сведения о файлах 
Function file_get(p_xid pls_integer) return xml_tp; 
Procedure file_delete(p_xid number); 
Function files_tbl return xml_tbl_tp pipelined parallel_enable; 
Function file_info_get(p_xml CLOB) return xml_info_tp; 
-- Анализ 
Function parse(p_xml CLOB) return number; 
-- Генерация 
Function generate(p_xid number:=0) return CLOB; -- генерировать файл форм 
-- при p_xid=0 генерировать расчетную форму РСВ-1 
-- Таблица данных разделов РСВ-1  
subType partname_tp is varchar2(64); 
subType partvalue_tp is varchar(128); 
-- Имена разделов данных РСВ-1 
part1_name constant partname_tp  :='РАЗДЕЛ_1';
part21_name constant partname_tp :='РАЗДЕЛ_2.1_';  -- РАЗДЕЛ_2.1_03 ,где 03 код_тарифа 
part251_name constant partname_tp:='РАЗДЕЛ_2.5.1'; 
part252_name constant partname_tp:='РАЗДЕЛ_2.5.2'; 
part4_name constant partname_tp  :='РАЗДЕЛ_4'; -- Имена полей титульной страницы, p_row=0 p_col=0 
fld_empcount constant partname_tp:='ТИТУЛ_КОЛИЧЕСТВО_ЗЛ';      -- количество ЗЛ 
fld_empavg constant partname_tp  :='ТИТУЛ_СРЕДНЕСПИСОЧНАЯ_ЧСЛ';-- среднесписочная численность 
-- Функции работы с данными РСВ-1 
Procedure parts_erase; 
Type part_names_tbl is table of partname_tp; 
Function parts_tbl(p_name varchar2:=null, p_row pls_integer:=null) 
    return part_names_tbl pipelined parallel_enable; 
Type part_value_tp is record 
( pname partname_tp 
, prow number 
, pcol number 
, pvalue partvalue_tp 
); 
Type part_values_tbl_tp is table of part_value_tp; 
Function part_values_tbl return part_values_tbl_tp pipelined parallel_enable; 
Procedure part_value_set 
(p_value varchar2, p_part varchar2, p_row pls_integer:=0, p_col pls_integer:=0);  
Procedure part_value_add 
(p_value number, p_part varchar2, p_row pls_integer:=0, p_col pls_integer:=0); 
Function part_value_get 
(p_part varchar2, p_row pls_integer:=0, p_col pls_integer:=0) return varchar2; 
/* 
    Вспомогательные функции 
*/ 
-- Преобразовать BLOB в XML-тип с учетом кодировки из XML-декларации
Function blob2xml(p_blob BLOB, p_csname varchar2 := null) return XMLType;
-- Преобразовать XML в BLOB (encoding="windows-1251")
Function xml2blob
( p_xml XMLType
, p_csname varchar2 := 'CL8MSWIN1251'  -- Oracle кодировка (CL8MSWIN1251, ALL32UTF8, ...) 
, p_debug boolean := false             -- true : построчно с отступом
) return BLOB;
-- Вернуть вид формы (СЗВ-6-1, СЗВ-6-2, ...) по номеру 
Function fn2name(p_fn number) return varchar2; 
-- Вернуть n-ю особенность учета из строки SPECS периода деятельности. 
Function period_specn_get(p_specs varchar2, p_n number) return varchar2; 
-- XML имя файла вида PFR-700-Y-2014-ORG-123-456-789012-DCK-34567-DPT-000000-DCK-00000.XML 
Function file_name_make(p_xid number :=0) return varchar2; 
-- XML формат рег. номера ПФР 000-000-000000 
Function pfn2num(p_fn varchar2) return number; 
Function num2pfn(p_fn number) return varchar2; 
-- XML формат СНИЛС 000-000-000 00 или 000-000-000-00 
Function snils2num(p_snils varchar2) return number; 
Function num2snils(p_snils number) return varchar2; -- возвращает 000-000-000 00 
-- XML код квартала: 1,2,3,4,6,9,0 Индекс квартала: 1,2,3,4 
Function pindex2x(p_index number, p_year number:=null) return number; 
Function x2pindex(p_quart number, p_year number:=null) return number; 
-- XML формат дат DD.MM.YYYY 
Function x2date(p_date varchar2) return date; 
Function date2x(p_date date) return varchar2; 
-- XML формат денег [-]99999999999.99 
Function x2money(p_money varchar2) return number;  
Function money2x(p_money number) return varchar2;  
-- XML encoding="windows-1251"
Function clob2blob(p_clob in CLOB, p_csname varchar2:='CL8MSWIN1251') return BLOB; 
Function blob2clob(p_blob in BLOB, p_csname varchar2:='CL8MSWIN1251') return CLOB;  
end; 
/
CREATE OR REPLACE PACKAGE BODY  "PF_XML6" is 
-- 
Function rsv_generate return clob; 
Function ns_remove(p_clob clob) return clob;
-- Итоги по XML-файлу 
Type xtotal_tp is record 
( xid number(5)  
, fcount number(3):=0 
, isum money_tp:=0 
, fsum money_tp:=0 
, cisum money_tp:=0 
, cfsum money_tp:=0 
, sumt money_tp:=0 -- заголовок файла СЗВ-6-4 
, sumb money_tp:=0 -- ... 
, sumo money_tp:=0 -- ... 
); 
-- 
Type form_tbi_tp is table of form_tp index by pls_integer; 
Type xml_tbi_tp is table of xml_tp index by binary_integer; --pls_integer; 
-- Пакет форм/файлов 
Type pack_tp is record 
( org org_tp         -- плательщик 
, forms form_tbi_tp  -- список форм 
, files xml_tbi_tp   -- список XML-файлов 
); 
-- Tаблица разделов данных РСВ-1  
Type cols_tp is table of partvalue_tp index by pls_integer; -- индекс=номер колонки 
Type rows_tp is table of cols_tp index by pls_integer;      -- индекс=код строки 
Type parts_tp is table of rows_tp index by partname_tp;     -- индекс=имя раздела-тарифа 
-- Аббревиатуры 
Type abbr_tbi_tp is table of varchar2(50) index by varchar2(10); 
c_abbr abbr_tbi_tp; 
-- Переменные сессии 
v_pack pack_tp;   -- пакет форм/файлов 
v_parts parts_tp; -- таблица разделов данных РСВ-1  
-- 
Type varr_tp is varray(9) of varchar2(200); 
-- Теги описей 
c_xhds constant varr_tp:=varr_tp 
( 'ВХОДЯЩАЯ_ОПИСЬ_ПО_СТРАХОВЫМ_ВЗНОСАМ'    -- СЗВ-6-1 
, 'ВХОДЯЩАЯ_ОПИСЬ_ПО_СТРАХОВЫМ_ВЗНОСАМ'    -- СЗВ-6-2 
, 'ВХОДЯЩАЯ_ОПИСЬ_ПО_СУММАМ_ВЫПЛАТ'        -- СЗВ-6-3 
, 'ВХОДЯЩАЯ_ОПИСЬ_ПО_СУММАМ_ВЫПЛАТ_И_ПО_СТРАХОВЫМ_ВЗНОСАМ' -- СЗВ-6-4 
, 'СВЕДЕНИЯ_ПО_ПАЧКЕ_ДОКУМЕНТОВ_РАЗДЕЛА_6' -- СЗВ-РСВ 
, '', '' 
, 'ВХОДЯЩАЯ_ОПИСЬ_ПО_СТРАХОВЫМ_ВЗНОСАМ'    -- АДВ-6 
, 'РАСЧЕТ_ПО_СТРАХОВЫМ_ВЗНОСАМ_НА_ОПС_И_ОМС_ПЛАТЕЛЬЩИКАМИ_ПРОИЗВОДЯЩИМИ_ВЫПЛАТЫ_ФЛ%' -- РСВ-1   
); 
-- Теги документов 
c_xdts constant varr_tp:=varr_tp 
( 'СВЕДЕНИЯ_О_СТРАХОВЫХ_ВЗНОСАХ_И_СТРАХОВОМ_СТАЖЕ_ЗЛ'-- СЗВ-6-1 
, 'СВЕДЕНИЯ_О_СТРАХОВЫХ_ВЗНОСАХ_И_СТРАХОВОМ_СТАЖЕ_ЗЛ'-- СЗВ-6-2 
, 'СВЕДЕНИЯ_О_СУММЕ_ВЫПЛАТ_И_ВОЗНАГРАЖДЕНИЙ'         -- СЗВ-6-3 
, 'СВЕДЕНИЯ_О_СУММЕ_ВЫПЛАТ_О_СТРАХОВЫХ_ВЗНОСАХ_И_СТРАХОВОМ_СТАЖЕ_ЗЛ' -- СЗВ-6-4 
, 'СВЕДЕНИЯ_О_СУММЕ_ВЫПЛАТ_И_СТРАХОВОМ_СТАЖЕ_ЗЛ'     -- СЗВ-РСВ 
, '','' 
, 'ОПИСЬ_СВЕДЕНИЙ_ПЕРЕДАВАЕМЫХ_СТРАХОВАТЕЛЕМ'        -- АДВ-6 
, '' -- РСВ-1 
); 
--  
Procedure raise_error(p_errno number) 
is 
begin 
  raise_application_error(-20200-p_errno,'PF_XML Ошибка в данных',true); 
end; 
-- Расшифровка аббревиатур 
Function abbr2x(p_abbr varchar2) return varchar2 
as 
begin 
  return c_abbr(p_abbr); 
exception 
  when others then return ''; 
end; 
-- Вернуть вид формы по номеру 
Function fn2name(p_fn number) return varchar2 
as 
begin 
  return abbr2x(p_fn); 
end; 
-- Получить индекс периода (1,2,3,4) из кода периода XML (1,2,3,4,6,9,0)  
Function x2pindex(p_quart number, p_year number:=null) return number 
is 
  l_index number; 
begin 
  if p_quart is null then return  null; end if; 
  if (p_year between 2011 and 2012) and p_quart=0 then return 4; end if;  
  if p_year between 2011 and 2013 then 
    l_index:=case when p_quart between 1 and 4 then p_quart else '-' end; 
  else 
    select decode(p_quart, 3, '1', 6, '2', 9, '3', 0, '4', '-') into l_index from dual; 
  end if; 
  return l_index; 
exception 
    when others then raise_error(1); 
end; 
-- Получить код квартала XML из индекса, в соответствии с номером (видом) формы 
Function pindex2x(p_index number, p_year number:=null)return number 
is 
  l_quart number; 
begin 
  if p_index is null then return null; end if; 
  if p_year between 2011 and 2013 then 
    l_quart:=case when p_index between 1 and 4 then p_index else '-' end; 
  else 
    select decode(p_index, 1, '3', 2, '6', 3, '9', 4, '0', '-') into l_quart from dual; 
  end if; 
  return l_quart; 
exception 
  when others then raise_error(1); 
end; 
-- Преобразования дат и денег 
Function date2x(p_date date) return varchar2 
as 
begin 
  return trim(to_char(p_date,'DD.MM.YYYY')); 
end; 
Function x2date(p_date varchar2) return date 
as 
begin 
  return to_date(trim(p_date),'DD.MM.YYYY'); 
end; 
Function money2x(p_money number) return varchar2 
as 
begin 
  return trim(to_char(p_money,'9999999999990D90','NLS_NUMERIC_CHARACTERS = ''. ''')); 
end; 
Function nvlMoney2x(p_money number) return varchar2 
as 
begin 
  return money2x(nvl(p_money,0)); 
end; 
Function x2money(p_money varchar2) return number 
as 
begin 
  return to_number(trim(p_money),'9999999999999D99','NLS_NUMERIC_CHARACTERS = ''. '''); 
end; 
-- Преобразование регистрационного номера организации в ПФР 999-999-999999 
Function num2pfn(p_fn number) return varchar2 
as 
begin 
  return trim(regexp_replace(to_char(p_fn,'000000000000') 
      ,'([[:digit:]]{3})([[:digit:]]{3})([[:digit:]]{6})','\1-\2-\3')); 
end; 
-- 
Function pfn2num(p_fn varchar2) return number 
as 
begin 
    return to_number(replace(replace(p_fn,'-',''),' ','')); 
--  return to_number(regexp_replace(p_fn 
--      ,'([[:digit:]]{3})-([[:digit:]]{3})-([[:digit:]]{6})','\1\2\3')); 
end; 
-- Преобразование СНИЛС застрахованного лица 999-999-999 99 (999-999-999-99) 
Function num2snils(p_snils number) return varchar2 
as 
begin 
  return trim(regexp_replace(to_char(p_snils,'00000000000') 
    ,'([[:digit:]]{3})([[:digit:]]{3})([[:digit:]]{3})([[:digit:]]{2})','\1-\2-\3 \4')); 
end; 
-- 
Function snils2num(p_snils varchar2) return number 
as 
begin 
  return pfn2num(p_snils); 
--  return to_number(regexp_replace(p_snils 
--      ,'([[:digit:]]{3})-([[:digit:]]{3})-([[:digit:]]{3})[- ]([[:digit:]]{2})','\1\2\3\4')); 
end; 
-- 
Function period_specn_get(p_specs varchar2, p_n number) return varchar2 
is 
  l_aspec APEX_APPLICATION_GLOBAL.VC_ARR2; 
begin 
  l_aspec:=APEX_UTIL.STRING_TO_TABLE(p_specs); 
  return l_aspec(p_n); 
exception 
  when others then return ''; 
end; 
-- ??? 
Procedure check_pindex(p_year number, p_index number) 
is 
begin 
   if p_year is null and p_index is null then return; end if; 
   if not nvl(p_index,0) between 1 and 4  
      or nvl(p_year,0) < 2011 then raise_error(1); end if; 
end; 
-- Получить DSK по xid 
Function dsk_get(p_xid number := 0) return number 
as 
begin 
  if nvl(p_xid,0) > 0 then return p_xid; end if; 
  if v_pack.files.count = 0 then return nvl(v_pack.org.sdeck,1); end if; 
  return v_pack.files.first - 1; 
end; 
-- Сгенерировать имя XML-файла по xid и org, проверить наличие данных организации 
Function file_name_make(p_xid number :=0) return varchar2 
as 
begin 
  check_pindex(v_pack.org.pyear,v_pack.org.pindex); 
  if v_pack.org.oname is null or v_pack.org.opfn is null or v_pack.org.oinn is null 
      or v_pack.org.okpp is null then raise_error(2); end if; 
  return 'PFR-700-Y-'||trim(to_char(v_pack.org.pyear))|| 
    '-ORG-'||num2pfn(v_pack.org.opfn)|| 
    '-DCK-'||trim(to_char(dsk_get(p_xid),'00000'))|| 
    '-DPT-000000-DCK-00000.XML'; 
end; 
-- PARTS Данные разделов РСВ-1. Очистить расчетную таблицу РСВ 
Procedure parts_erase 
as 
l_pname partname_tp:=v_parts.first; 
begin 
  if v_parts.count=0 then return; end if; 
  loop 
    continue when v_parts(l_pname).count=0; 
    for c in v_parts(l_pname).first..v_parts(l_pname).last loop 
      continue when not v_parts(l_pname).exists(c);   
      v_parts(l_pname)(c).delete; 
    end loop; 
    v_parts(l_pname).delete; 
    exit when l_pname=v_parts.last; 
    l_pname:=v_parts.next(l_pname); 
  end loop; 
  v_parts.delete; 
end; 
-- PARTS  Таблица имен разделов/номеров строк/столбцов 
Function parts_tbl 
( p_name varchar2:=null 
, p_row pls_integer:=null 
) return part_names_tbl pipelined parallel_enable 
is 
l_val varchar(32); 
begin 
  if p_name is null then 
    if v_parts.count=0 then return; end if; 
    l_val:=v_parts.first; 
    loop 
      pipe row(l_val); 
      exit when l_val=v_parts.last; 
      l_val:=v_parts.next(l_val); 
    end loop; 
  else 
    if not v_parts.exists(upper(p_name)) then return; end if; 
    if p_row is null then 
      for i in v_parts(upper(p_name)).first..v_parts(upper(p_name)).last loop 
        continue when not v_parts(upper(p_name)).exists(i); 
        pipe row(to_char(i)); 
      end loop; 
    else 
      if not v_parts(upper(p_name)).exists(p_row) then return; end if; 
      for i in v_parts(upper(p_name))(p_row).first..v_parts(upper(p_name))(p_row).last loop 
        continue when not v_parts(upper(p_name))(p_row).exists(i); 
        pipe row(to_char(i)); 
      end loop; 
    end if; 
  end if; 
  return; 
end; 
-- 
Function part_values_tbl return part_values_tbl_tp pipelined parallel_enable 
is 
l_v part_value_tp; 
l_pname partname_tp; 
begin 
  if v_parts.count = 0 then return; end if; 
  for l_pname in v_parts.first..v_parts.last 
  loop 
    for r in v_parts(l_pname).first..v_parts(l_pname).last 
    loop 
       continue when not v_parts(l_pname).exists(r); 
       for c in v_parts(l_pname)(r).first..v_parts(l_pname)(r).last 
       loop 
         continue when not v_parts(l_pname)(r).exists(c); 
         l_v.pname := l_pname; 
         l_v.prow := r; 
         l_v.pcol := c; 
         l_v.pvalue := v_parts(l_pname)(r)(c); 
         pipe row(l_v); 
       end loop; 
    end loop; 
  end loop; 
  return; 
end; 
-- PARTS Присвоить значение ячейке таблицы 
Procedure part_value_set 
( p_value varchar2 
, p_part varchar2 
, p_row pls_integer:=0 
, p_col pls_integer:=0 
) 
as 
begin 
  v_parts(upper(p_part))(p_row)(p_col):=p_value; 
end; 
-- PARTS Извлечь значение из ячейки расчетной таблицы РСВ 
Function part_value_get 
( p_part varchar2 
, p_row pls_integer:=0 
, p_col pls_integer:=0 
) return varchar2 
as 
begin 
  return v_parts(upper(p_part))(p_row)(p_col); 
exception 
  when no_data_found then return null; 
end; 
-- PARTS Сложение в ячейке расчетной таблицы РСВ 
Procedure part_value_add 
( p_value number 
, p_part varchar2 
, p_row pls_integer 
, p_col pls_integer 
) 
as 
begin 
  v_parts(upper(p_part))(p_row)(p_col):= 
    nvl(part_value_get(p_part,p_row,p_col),0)+nvl(p_value,0); 
end; 
-- Инициализация 
Procedure init(p_org org_tp) 
is 
begin 
  parts_erase; 
  v_pack.files.delete; 
  if v_pack.forms.count > 0 then 
    for i in v_pack.forms.first..v_pack.forms.last 
    loop 
      form_delete(i); 
    end loop; 
  end if; 
  v_pack.org:=p_org; 
end; 
-- 
Procedure init 
as 
l_nullorg org_tp; 
begin 
  init(l_nullorg); 
end; 
-- ORG Установить сведения об организации 
Procedure org_set(p_org org_tp) 
as 
begin 
  v_pack.org:=p_org; 
end; 
-- ORG Получить сведения об организации 
Function org_get return org_tp 
as 
begin 
  return v_pack.org; 
end; 
-- FORM Очистить пользовательскую форму 
Procedure form_clear(p_frm in out nocopy form_tp) 
as 
l_nullhdr hdr_tp; 
begin 
    p_frm.periods.delete; 
    p_frm.incomes.delete; 
    p_frm.payments.delete; 
    p_frm.corrs.delete; 
    p_frm.hdr:=l_nullhdr; 
end; 
-- FORM Удалить форму из списка 
Procedure form_delete(p_fid number) 
is 
l_xid number; 
begin 
  if v_pack.forms.exists(p_fid) then 
    l_xid:=v_pack.forms(p_fid).hdr.xid; 
    form_clear(v_pack.forms(p_fid)); 
    v_pack.forms.delete(p_fid); 
    if not v_pack.files.exists(l_xid) then return; end if; 
    v_pack.files(l_xid).xfcount:=v_pack.files(l_xid).xfcount-1; 
    if v_pack.files(l_xid).xfcount<=0 then file_delete(l_xid); end if;     
  end if; 
end; 
-- FORM Получить форму по индексу 
Function form_get(p_fid number) return form_tp 
as 
begin 
  return v_pack.forms(p_fid); 
end; 
-- FORM Добавить форму в список и ассоциировать с XML-файлом 
Procedure form_add(p_frm in out nocopy form_tp) 
as 
l_xkey varchar2(32); 
l_xid number:=0; 
l_fid number; 
i pls_integer; 
begin 
  if nvl(p_frm.hdr.ftype,'-') not in ('ИСХ','КОР','ОТМ') then raise_error(3); end if; 
  if p_frm.hdr.ftype <> 'ИСХ' then 
    check_pindex(p_frm.hdr.cpyear, p_frm.hdr.cpindex); 
  else 
    p_frm.hdr.cpyear:=null; 
    p_frm.hdr.cpindex:=null; 
  end if; 
  p_frm.hdr.fn := case nvl(p_frm.hdr.cpyear,v_pack.org.pyear) 
      when 2010 then fn_szv1 
      when 2011 then fn_szv1 
      when 2012 then fn_szv1 
      when 2013 then fn_szv4 
      when 2014 then fn_szvr 
      when 2015 then fn_szvr 
      when 2016 then fn_szvr 
      else null end; 
  if p_frm.hdr.fn is null then raise_error(3); end if; 
  l_xkey:=p_frm.hdr.fn|| ':' || 
    p_frm.hdr.ftype   || ':' || 
    p_frm.hdr.cpindex || ':' || p_frm.hdr.cpyear || ':' || 
    p_frm.hdr.contype || ':' || p_frm.hdr.emptype; 
-- определим id формы 
  l_fid:=nvl(p_frm.hdr.fid 
      , case when v_pack.forms.count=0 then 1 else v_pack.forms.last+1 end ); 
-- удалим форму, если существует 
  form_delete(l_fid); 
-- получить id файла по ключу 
  for xt in  
    (select xid from table(files_tbl) where xkey=l_xkey and xfcount < 200) 
  loop 
    l_xid:=xt.xid; 
    exit; 
  end loop; 
  if l_xid = 0 then 
-- нет свободных файлов - добавим       
    l_xid := case when v_pack.files.count=0  
      then nvl(v_pack.org.sdeck,1)+1 else v_pack.files.last+1 end; 
    v_pack.files(l_xid).xid:=l_xid; 
    v_pack.files(l_xid).xfcount:=0; 
    v_pack.files(l_xid).xkey:=l_xkey; 
    v_pack.files(l_xid).fn:=p_frm.hdr.fn; 
    v_pack.files(l_xid).ftype:=p_frm.hdr.ftype; 
    v_pack.files(l_xid).cpindex:=p_frm.hdr.cpindex; 
    v_pack.files(l_xid).cpyear:=p_frm.hdr.cpyear; 
    v_pack.files(l_xid).contype:=p_frm.hdr.contype; 
    v_pack.files(l_xid).emptype:=p_frm.hdr.emptype; 
  end if; 
  p_frm.hdr.xid:=l_xid; 
  p_frm.hdr.fid:=l_fid; 
 -- присвоить FID записям формы 
  i:=p_frm.incomes.first; 
  while i is not null loop 
    p_frm.incomes(i).fid:=l_fid; 
    i:=p_frm.incomes.next(i); 
  end loop; 
  i:=p_frm.payments.first; 
  while i is not null loop 
    p_frm.payments(i).fid:=l_fid; 
    i:=p_frm.payments.next(i); 
  end loop; 
  i:=p_frm.periods.first; 
  while i is not null loop 
    p_frm.periods(i).fid:=l_fid; 
    i:=p_frm.periods.next(i); 
  end loop; 
  i:=p_frm.corrs.first; 
  while i is not null loop 
    p_frm.corrs(i).fid:=l_fid; 
    i:=p_frm.corrs.next(i); 
  end loop; 
-- добавить форму в список 
  v_pack.forms(l_fid):=p_frm; 
-- увеличить счетчик форм файла 
  v_pack.files(l_xid).xfcount:=v_pack.files(l_xid).xfcount+1; 
  
end; 
-- FORM Таблица заголовков форм 
Function forms_tbl return hdr_tbl_tp pipelined parallel_enable 
is 
begin 
  if v_pack.forms.count=0 then return; end if; 
  for i in v_pack.forms.first..v_pack.forms.last loop 
    continue when not v_pack.forms.exists(i); 
    pipe row(v_pack.forms(i).hdr); 
  end loop; 
  return; 
end; 
-- FORM Таблица дополнительных выплат 
Function payments_tbl(p_fid number:=null) return pmt_tbl_tp pipelined parallel_enable 
is 
ff pls_integer:=nvl(p_fid, v_pack.forms.first); 
lf pls_integer:=nvl(p_fid, v_pack.forms.last); 
begin 
for fid in ff..lf loop 
  continue when not v_pack.forms.exists(fid); 
  if v_pack.forms(fid).payments.count > 0 then 
    for i in v_pack.forms(fid).payments.first..v_pack.forms(fid).payments.last 
    loop 
      continue when not v_pack.forms(fid).payments.exists(i); 
      pipe row(v_pack.forms(fid).payments(i)); 
    end loop; 
  end if; 
end loop; 
return; 
end; 
-- FORM Таблица доходов/баз 
Function incomes_tbl(p_fid number:=null) return inc_tbl_tp pipelined parallel_enable 
is 
ff pls_integer; 
lf pls_integer; 
begin 
ff:=nvl(p_fid, v_pack.forms.first); 
lf:=nvl(p_fid, v_pack.forms.last); 
for fid in ff..lf loop 
  continue when not v_pack.forms.exists(fid); 
  if v_pack.forms(fid).incomes.count > 0 then 
    for i in v_pack.forms(fid).incomes.first..v_pack.forms(fid).incomes.last 
    loop 
      continue when not v_pack.forms(fid).incomes.exists(i); 
      pipe row(v_pack.forms(fid).incomes(i)); 
    end loop; 
  end if; 
end loop; 
return; 
end; 
-- FORM Таблица периодов 
Function periods_tbl(p_fid number:=null) return pd_tbl_tp pipelined parallel_enable 
is 
ff pls_integer:=nvl(p_fid, v_pack.forms.first); 
lf pls_integer:=nvl(p_fid, v_pack.forms.last); 
begin 
for fid in ff..lf loop 
  continue when not v_pack.forms.exists(fid); 
  if v_pack.forms(fid).periods.count > 0 then 
    for i in v_pack.forms(fid).periods.first..v_pack.forms(fid).periods.last 
    loop 
      continue when not v_pack.forms(fid).periods.exists(i); 
      pipe row(v_pack.forms(fid).periods(i)); 
    end loop; 
  end if; 
end loop; 
return; 
end; 
-- FORM Таблица корректировок 
Function corrs_tbl(p_fid number:=null) return cor_tbl_tp pipelined parallel_enable 
is 
ff pls_integer:=nvl(p_fid, v_pack.forms.first); 
lf pls_integer:=nvl(p_fid, v_pack.forms.last); 
begin 
for fid in ff..lf loop 
  continue when not v_pack.forms.exists(fid); 
  if v_pack.forms(fid).corrs.count > 0 then 
    for i in v_pack.forms(fid).corrs.first..v_pack.forms(fid).corrs.last 
    loop 
      continue when not v_pack.forms(fid).corrs.exists(i); 
      pipe row(v_pack.forms(fid).corrs(i)); 
    end loop; 
  end if; 
end loop; 
return; 
end; 
-- XML Получить сведения о файле 
Function file_get(p_xid pls_integer) return xml_tp 
as 
begin 
  return v_pack.files(p_xid); 
end; 
-- XML Удалить файл и связанные формы 
Procedure file_delete(p_xid number) 
as 
begin 
if v_pack.forms.count>0 then  
  for i in v_pack.forms.first..v_pack.forms.last loop 
    continue when not v_pack.forms.exists(i); 
    if v_pack.forms(i).hdr.xid=p_xid then form_delete(i); end if; 
  end loop; 
end if; 
if not v_pack.files.exists(p_xid) then return; end if; 
v_pack.files.delete(p_xid); 
end; 
-- XML Получить таблицу файлов 
Function files_tbl return xml_tbl_tp pipelined parallel_enable 
is 
begin 
  if v_pack.files.count=0 then return; end if; 
  for i in v_pack.files.first..v_pack.files.last loop 
    continue when not v_pack.files.exists(i); 
    pipe row(v_pack.files(i)); 
  end loop; 
  return; 
end; 
/* 
  АНАЛИЗ XML-ФАЙЛОВ ПФР 
*/ 
-- Анализ РСВ-1 Раздел 1 
Procedure rsv1_parse(p_xml xmltype) 
as 
begin 
  if p_xml is null then return; end if; -- выход из рекурсии 
  for xt in 
      ( select scode, x2money(ifsum) ifsum, x2money(isum) isum, x2money(fsum) fsum 
        , x2money(suma1) suma1, x2money(suma2) suma2, x2money(osum) osum 
        , bxml 
        from XMLTable('/*' passing p_xml 
          columns "SCODE" number path 'КодСтроки' 
         , "IFSUM" varchar2(15) path 'СтраховыеВзносыОПС' 
         , "ISUM" varchar2(15) path 'ОПСстраховаяЧасть' 
         , "FSUM" varchar2(15) path 'ОПСнакопительнаяЧасть' 
         , "SUMA1" varchar2(15) path 'ВзносыПоДопТарифу1' 
         , "SUMA2" varchar2(15) path 'ВзносыПоДопТарифу2_18' 
         , "OSUM" varchar2(15) path 'СтраховыеВзносыОМС' 
         , "BXML" xmltype path '/' 
       ) ) 
  loop 
    if xt.scode is not null then 
      part_value_set(xt.ifsum,part1_name,xt.scode,3); 
      part_value_set(xt.isum,part1_name,xt.scode,4); 
      part_value_set(xt.fsum,part1_name,xt.scode,5); 
      part_value_set(xt.suma1,part1_name,xt.scode,6); 
      part_value_set(xt.suma2,part1_name,xt.scode,7); 
      part_value_set(xt.osum,part1_name,xt.scode,8); 
    else 
--dbms_output.put_line(xt.bxml.getstringval()); 
      for bt in ( select column_value xml from XMLTable('*/*' passing xt.bxml )) 
      loop  
        rsv1_parse(bt.xml); -- рекурсия 
      end loop; 
    end if; 
  end loop; 
end; 
-- Анализ РСВ-1 Раздел 2.1 
Procedure rsv21_parse(p_xml xmltype, p_tcode number) 
as 
l_ccode varchar2(2):=trim(to_char(p_tcode,'00')); 
begin 
--dbms_output.put_line(p_xml.getstringval()); 
  for xt in 
    ( select scode 
        , x2money(isum0) isum0, x2money(isum1) isum1 
        , x2money(isum2) isum2, x2money(isum3) isum3 
        , x2money(empc0) empc0, x2money(empc1) empc1 
        , x2money(empc2) empc2, x2money(empc3) empc3 
        from XMLTable('/*/*' passing p_xml 
          columns "SCODE" number path 'КодСтроки' 
         , "ISUM0" varchar2(15) path 'РасчетСумм/СуммаВсегоСначалаРасчетногоПериода' 
         , "ISUM1" varchar2(15) path 'РасчетСумм/СуммаПоследние1месяц' 
         , "ISUM2" varchar2(15) path 'РасчетСумм/СуммаПоследние2месяц' 
         , "ISUM3" varchar2(15) path 'РасчетСумм/СуммаПоследние3месяц' 
         , "EMPC0" varchar2(15) path 'КоличествоЗЛ_Всего' 
         , "EMPC1" varchar2(15) path 'КоличествоЗЛ_1месяц' 
         , "EMPC2" varchar2(15) path 'КоличествоЗЛ_2месяц' 
         , "EMPC3" varchar2(15) path 'КоличествоЗЛ_3месяц' 
        ) ) 
  loop 
    part_value_set(nvl(xt.empc0,xt.isum0),part21_name||l_ccode,xt.scode,3); 
    part_value_set(nvl(xt.empc1,xt.isum1),part21_name||l_ccode,xt.scode,4); 
    part_value_set(nvl(xt.empc2,xt.isum2),part21_name||l_ccode,xt.scode,5); 
    part_value_set(nvl(xt.empc3,xt.isum3),part21_name||l_ccode,xt.scode,6); 
  end loop; 
  return; 
end; 
-- Анализ РСВ-1 Раздел 2.5 
Procedure rsv25_parse(p_xml xmltype, p_subpart number) 
as 
begin 
--dbms_output.put_line(p_xml.getstringval()); 
  for xt in 
    ( select rownum rn, scode 
        , x2money(sumb) sumb, x2money(ifsum) ifsum 
        , empcnt, xname, cpcode, cpyear 
        , x2money(cifsum) cifsum, x2money(cisum) cisum 
        , x2money(cfsum) cfsum 
        from XMLTable('/*/*' passing p_xml 
          columns "SCODE" number path 'НомерПП' 
         , "SUMB" varchar2(15) path 'БазаДляНачисленияСтраховыхВзносовНеПревышающаяПредельную' 
         , "IFSUM" varchar2(15) path 'СтраховыхВзносовОПС' 
         , "EMPCNT" number path 'КоличествоЗЛвПачке' 
         , "XNAME" varchar2(128) path 'ИмяФайла' 
         , "CPCODE" number path 'КорректируемыйОтчетныйПериод/Квартал' 
         , "CPYEAR" number path 'КорректируемыйОтчетныйПериод/Год' 
         , "CIFSUM" varchar2(15) path 'ДоначисленоСтраховыхВзносовОПС' 
         , "CISUM" varchar2(15) path 'ДоначисленоНаСтраховуюЧасть' 
         , "CFSUM" varchar2(15) path 'ДоначисленоНаНакопительнуюЧасть' 
        ) ) 
  loop 
    continue when xt.empcnt is null; -- пропустить количество пачек 
    case p_subpart  
      when 1 then 
        part_value_set(xt.scode,part251_name,nvl(xt.scode,0),1); 
        part_value_set(xt.sumb,part251_name,nvl(xt.scode,0),2); 
        part_value_set(xt.ifsum,part251_name,nvl(xt.scode,0),3); 
        part_value_set(xt.empcnt,part251_name,nvl(xt.scode,0),4); 
        part_value_set(xt.xname,part251_name,nvl(xt.scode,0),5); 
      when 2 then 
        part_value_set(xt.scode,part252_name,nvl(xt.scode,0),1); 
        part_value_set(case when xt.cpcode is not null  
            then x2pindex(xt.cpcode,xt.cpyear) else null end 
            , part252_name, nvl(xt.scode,0),2);       
        part_value_set(xt.cpyear,part252_name,nvl(xt.scode,0),3); 
        part_value_set(xt.cifsum,part252_name,nvl(xt.scode,0),4); 
        part_value_set(xt.cisum,part252_name,nvl(xt.scode,0),5); 
        part_value_set(xt.cfsum,part252_name,nvl(xt.scode,0),6); 
        part_value_set(xt.empcnt,part252_name,nvl(xt.scode,0),7); 
        part_value_set(xt.xname,part252_name,nvl(xt.scode,0),8); 
      else null;  
    end case;   
  end loop; 
end; 
-- Анализ РСВ-1 2014-2015г 
Function rsv_parse 
( p_xml xmltype 
) return number 
as 
l_xml xmltype; 
begin 
  parts_erase; 
  select nvl(xml4, xml5) into l_xml 
    from XMLTable('/ФайлПФР/ПачкаВходящихДокументов' passing p_xml  
      columns 
         "XML4" xmltype path 'РАСЧЕТ_ПО_СТРАХОВЫМ_ВЗНОСАМ_НА_ОПС_И_ОМС_ПЛАТЕЛЬЩИКАМИ_ПРОИЗВОДЯЩИМИ_ВЫПЛАТЫ_ФЛ_2014' 
        ,"XML5" xmltype path 'РАСЧЕТ_ПО_СТРАХОВЫМ_ВЗНОСАМ_НА_ОПС_И_ОМС_ПЛАТЕЛЬЩИКАМИ_ПРОИЗВОДЯЩИМИ_ВЫПЛАТЫ_ФЛ_2015' 
                 ); 
  select empcount, empavg 
--    , okved 
    into  v_parts(fld_empcount)(0)(0), v_parts(fld_empavg)(0)(0) 
--      , v_parts(fld_orgokved)(0)(0) 
      from XMLTable('/' passing l_xml  
          columns  "EMPCOUNT" number path 'КоличествоЗЛ' 
      , "EMPAVG" number path 'СреднесписочнаяЧисленность' 
--      , "OKVED" varchar2(16) path 'КодПоОКВЭД' 
      ); 
  for xt in 
    ( select column_value xml  
        from XMLTable('*/Раздел1РасчетПоНачисленнымУплаченным2014/*' passing l_xml 
        ) ) 
  loop 
      rsv1_parse(xt.xml); 
  end loop; 
  for xt in 
    ( select tcode, nvl(ixml4,ixml5) ixml, mxml 
        from XMLTable('*/Раздел2РасчетПоТарифуИдопТарифу/Раздел_2_1' passing l_xml 
          columns "TCODE" number  path 'КодТарифа' 
         , "IXML4" xmltype path 'НаОбязательноеПенсионноеСтрахование2014' 
         , "IXML5" xmltype path 'НаОбязательноеПенсионноеСтрахование'           
         , "MXML" xmltype path 'НаОбязательноеМедицинскоеСтрахование' 
        ) ) 
  loop 
    rsv21_parse(xt.ixml,xt.tcode); 
    rsv21_parse(xt.mxml,xt.tcode); 
  end loop; 
  for xt in 
    ( select xml1, xml2 
        from XMLTable('*/Раздел2РасчетПоТарифуИдопТарифу/Раздел_2_5' passing l_xml 
        columns xml1 xmltype path 'ПереченьПачекИсходныхСведенийПУ' 
         , xml2 xmltype path 'ПереченьПачекКорректирующихСведенийПУ')) 
  loop 
    rsv25_parse(xt.xml1,1); 
    rsv25_parse(xt.xml2,2); 
  end loop; 
  select nvl(xml4, xml5) into l_xml 
    from XMLTable('/*' passing l_xml  
      columns 
         "XML4" xmltype path 'Раздел4СуммыДоначисленныхСтраховыхВзносов2014' 
        ,"XML5" xmltype path 'Раздел4' 
                 ); 
  for xt in 
    ( select scode, osn, cosna, pyear, pmon 
        , x2money(cifsum) cifsum, x2money(cifsumo) cifsumo 
        , x2money(cisum) cisum, x2money(cisumo) cisumo, x2money(cfsum) cfsum 
        , x2money(ca1sum) ca1sum, x2money(ca2sum) ca2sum, x2money(ca21sum) ca21sum 
        , x2money(cmsum) cmsum 
       from XMLTable('*/*' passing l_xml 
--       from XMLTable('*/'Раздел4СуммыДоначисленныхСтраховыхВзносов2014/*' passing l_xml 
         columns "SCODE" number path 'НомерПП' 
           ,"OSN" number path 'ОснованиеДляДоначисления' 
           ,"COSNA" number path 'КодОснованияДляДопТарифа' 
           ,"PYEAR" number path 'Год' 
           ,"PMON" number path 'Месяц' 
           ,"CIFSUM" varchar2(15) path 'СуммаДоначисленныхВзносовОПС2014всего' 
           ,"CIFSUMO" varchar2(15) path 'СуммаДоначисленныхВзносовОПС2014превыщающие' 
           ,"CISUM" varchar2(15) path 'СуммаДоначисленныхВзносовНаСтраховуюВсего' 
           ,"CISUMO" varchar2(15) path 'СуммаДоначисленныхВзносовНаСтраховуюПревышающие' 
           ,"CFSUM" varchar2(15) path 'СуммаДоначисленныхВзносовНаНакопительную' 
           ,"CA1SUM" varchar2(15) path 'СтраховыхДоначисленныхВзносовПоДопТарифуЧ1' 
           ,"CA2SUM" varchar2(15) path 'СтраховыхДоначисленныхВзносовПоДопТарифуЧ2' 
           ,"CA21SUM" varchar2(15) path 'СтраховыхДоначисленныхВзносовПоДопТарифуЧ2_1' 
           ,"CMSUM" varchar2(15) path 'СтраховыеВзносыОМС' 
     )  ) 
  loop 
    if xt.scode is not null then 
      part_value_set(xt.scode,part4_name,nvl(xt.scode,0),1); 
      part_value_set(xt.osn,part4_name,nvl(xt.scode,0),2); 
      part_value_set(xt.cosna,part4_name,nvl(xt.scode,0),3); 
      part_value_set(xt.pyear,part4_name,nvl(xt.scode,0),4); 
      part_value_set(xt.pmon,part4_name,nvl(xt.scode,0),5); 
    end if; 
    part_value_set(xt.cifsum,part4_name,nvl(xt.scode,0),6); 
    part_value_set(xt.cifsumo,part4_name,nvl(xt.scode,0),7); 
    part_value_set(xt.cisum,part4_name,nvl(xt.scode,0),8); 
    part_value_set(xt.cisumo,part4_name,nvl(xt.scode,0),9); 
    part_value_set(xt.cfsum,part4_name,nvl(xt.scode,0),10); 
    part_value_set(xt.ca1sum,part4_name,nvl(xt.scode,0),11); 
    part_value_set(xt.ca2sum,part4_name,nvl(xt.scode,0),12); 
    part_value_set(xt.ca21sum,part4_name,nvl(xt.scode,0),13); 
    part_value_set(xt.cmsum,part4_name,nvl(xt.scode,0),14); 
  end loop;     
  return 0; 
end; 
-- Анализ. Сведения о корректировках 
Function cor_parse(p_xdoc xmltype) return cor_tbl_tp 
as 
  l_cortb cor_tbl_tp:=cor_tbl_tp(); 
begin 
  for xt in 
    ( select rownum i, column_value x  
        from XMLTable('/*/СведенияОкорректировках' passing p_xdoc)) 
  loop 
    continue when xt.x is null; 
    l_cortb.extend(); 
    xt.i:=l_cortb.last(); 
    select case when cpyear is null then null else x2pindex(cpcode,cpyear) end 
      , cpyear, x2money(dpsum), x2money(disum), x2money(dfsum) 
      into l_cortb(xt.i).cpindex,l_cortb(xt.i).cpyear 
        , l_cortb(xt.i).dpsum, l_cortb(xt.i).disum, l_cortb(xt.i).dfsum 
      from XMLTable('/' passing xt.x 
            columns cpcode number(1) path 'Квартал' 
            , cpyear number(4) path 'Год' 
            , dpsum varchar2(15) path 'СуммаДоначисленныхВзносовОПС' 
            , disum varchar2(15) path 'СуммаДоначисленныхВзносовНаСтраховую' 
            , dfsum varchar2(15) path 'СуммаДоначисленныхВзносовНаНакопительную'); 
  end loop; 
  return l_cortb; 
end; 
-- Анализ. Периоды работы. 
Function pd_parse(p_xdoc xmltype) return pd_tbl_tp 
as 
  l_pdtb pd_tbl_tp:=pd_tbl_tp(); 
begin 
  for xt in  
    ( select rownum as i, column_value as x 
        from XMLTable('/*/СтажевыйПериод' passing p_xdoc)) 
  loop 
    continue when xt.x is null; 
    l_pdtb.extend(); 
    xt.i := l_pdtb.last(); 
    select nn, x2date(sdatec), x2date(edatec) 
        , terr, x2money(terrcc), dd 
        , replace(rtrim(s1||' '||s2||' '|| 
            s3||nvl2(s3,' '||s4||' '||s5||' '||s6||' '||s7||' ','     ')|| 
            s8||nvl2(s8,' '||s9||' '||s10||' '||s11||' '||s12||' '||x2money(s13),'')),' ',':') 
      into l_pdtb(xt.i).nn, l_pdtb(xt.i).sdate, l_pdtb(xt.i).edate 
        , l_pdtb(xt.i).terr, l_pdtb(xt.i).terrc, l_pdtb(xt.i).dd 
        , l_pdtb(xt.i).specs 
      from XMLTable('/' passing xt.x 
        columns "NN" number path 'НомерСтроки' 
        , "SDATEC" varchar2(10) path 'ДатаНачалаПериода' 
        , "EDATEC" varchar2(10) path 'ДатаКонцаПериода' 
        , "TERR"  varchar2(10) path 'ЛьготныйСтаж/ОсобенностиУчета/ТерриториальныеУсловия/ОснованиеТУ' 
        , "TERRCC" varchar2(10) path 'ЛьготныйСтаж/ОсобенностиУчета/ТерриториальныеУсловия/Коэффициент' 
        , "S1" varchar2(50) path 'ЛьготныйСтаж/ОсобенностиУчета/ОсобыеУсловияТруда/ОснованиеОУТ' 
        , "S2" varchar2(50) path 'ЛьготныйСтаж/ОсобенностиУчета/ОсобыеУсловияТруда/ПозицияСписка' 
        , "S3" varchar2(50) path 'ЛьготныйСтаж/ОсобенностиУчета/ИсчисляемыйСтаж/ОснованиеИС' 
        , "S4" varchar2(5) path 'ЛьготныйСтаж/ОсобенностиУчета/ИсчисляемыйСтаж/ВыработкаВчасах/Часы' 
        , "S5" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ИсчисляемыйСтаж/ВыработкаВчасах/Минуты' 
        , "S6" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ИсчисляемыйСтаж/ВыработкаКалендарная/ВсеМесяцы' 
        , "S7" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ИсчисляемыйСтаж/ВыработкаКалендарная/ВсеДни' 
        , "DD" varchar2(50) path 'ЛьготныйСтаж/ОсобенностиУчета/ДекретДети' 
        , "S8" varchar2(50) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ОснованиеВЛ' 
        , "S9" varchar2(5) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ВыработкаВчасах/Часы' 
        , "S10" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ВыработкаВчасах/Минуты' 
        , "S11" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ВыработкаКалендарная/ВсеМесяцы' 
        , "S12" varchar2(2) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ВыработкаКалендарная/ВсеДни' 
        , "S13" varchar2(5) path 'ЛьготныйСтаж/ОсобенностиУчета/ВыслугаЛет/ДоляСтавки' 
      ); 
  end loop; 
  return l_pdtb; 
exception 
-- есть дополнительные стажевые периоды, не поддерживается! 
  when TOO_MANY_ROWS then raise_error(4); 
end; 
-- Анализ. Доходы и базы. 
Function inc_parse(p_xdoc xmltype) return inc_tbl_tp 
as 
  l_intb inc_tbl_tp := inc_tbl_tp(); 
begin 
  for xt in 
    ( select rownum i, column_value x5 
        from XMLTable('/*/СведенияОсуммеВыплатИвознагражденийВпользуЗЛ' passing p_xdoc)) 
  loop 
    l_intb.extend(); 
    xt.i:=l_intb.last(); 
    select nvl(pmon,0), emptype, x2money(sumtc), x2money(sumbc) 
        , x2money(sumbgc), x2money(sumoc) 
      into l_intb(xt.i).pmon, l_intb(xt.i).emptype, l_intb(xt.i).sumt 
        , l_intb(xt.i).sumb, l_intb(xt.i).sumbg, l_intb(xt.i).sumo 
      from XMLTable('/' passing xt.x5 
         columns "PMON" number path 'Месяц' 
         , "EMPTYPE" varchar2(10) path 'КодКатегории' 
         , "SUMTC" varchar2(15) path 'СуммаВыплатИныхВознаграждений' 
         , "SUMBC" varchar2(15) path 'НеПревышающиеВсего' 
         , "SUMBGC" varchar2(15) path 'НеПревышающиеПоДоговорам' 
         , "SUMOC" varchar2(15) path 'ПревышающиеПредельную'); 
  end loop; 
  if l_intb.count > 0 then return l_intb; end if; 
  for xt in 
    ( select rownum i, column_value x4 
        from XMLTable('/*/СуммаВыплатИвознагражденийВпользуЗЛ' passing p_xdoc)) 
  loop 
    l_intb.extend(); 
    xt.i:=l_intb.last(); 
    select nvl(pmon,0), x2money(sumtc), x2money(sumbc), x2money(sumoc) 
      into l_intb(xt.i).pmon, l_intb(xt.i).sumt 
         , l_intb(xt.i).sumb, l_intb(xt.i).sumo 
      from XMLTable('/' passing xt.x4 
         columns "PMON" number path 'Месяц' 
         , "SUMTC" varchar2(15) path 'СуммаВыплатВсего' 
         , "SUMBC" varchar2(15) path 'СуммаВыплатНачисленыСтраховыеВзносыНеПревышающие' 
         , "SUMOC" varchar2(15) path 'СуммаВыплатНачисленыСтраховыеВзносыПревышающие'); 
  end loop; 
  if l_intb.count > 0 then return l_intb; end if; 
  for xt in 
    ( select rownum i, column_value x3 
        from XMLTable('/*/СуммаВыплатИвознаграждений' passing p_xdoc)) 
  loop 
    l_intb.extend(); 
    xt.i:=l_intb.last(); 
    select nvl(pmon,0), x2money(sumtc), x2money(sumbc) 
          into l_intb(xt.i).pmon, l_intb(xt.i).sumt 
         , l_intb(xt.i).sumb 
      from XMLTable('/' passing xt.x3 
         columns "PMON" number path 'Месяц' 
         , "SUMTC" varchar2(15) path 'СуммаВыплатВсего' 
         , "SUMBC" varchar2(15) path 'СуммаВыплатНачисленыСтраховыеВзносы'); 
  end loop; 
  return l_intb; 
end; 
-- Анализ. Выплаты. 
Function pmt_parse(p_xdoc xmltype) return pmt_tbl_tp 
as 
  l_pmtb pmt_tbl_tp:=pmt_tbl_tp(); 
begin 
  for xt in 
    ( select rownum i, column_value x5 
--        from XMLTable('/*/СведенияОсуммеВыплатИвознагражденийВпользуЗЛ' passing p_xdoc)) 
        from XMLTable('/*/СведенияОсуммеВыплатИвознагражденийПоДопТарифу' passing p_xdoc)) 
  loop 
    l_pmtb.extend(); 
    xt.i:=l_pmtb.last(); 
    select nvl(pmon,0), acode, x2money(suma1c), x2money(suma2c) 
      into l_pmtb(xt.i).pmon, l_pmtb(xt.i).acode 
         , l_pmtb(xt.i).suma1, l_pmtb(xt.i).suma2 
      from XMLTable('/' passing xt.x5 
         columns "PMON" number path 'Месяц' 
         , "ACODE" varchar2(15) path 'КодСпециальнойОценкиУсловийТруда' 
         , "SUMA1C" varchar2(15) path 'СуммаВыплатПоДопТарифу27-1' 
         , "SUMA2C" varchar2(15) path 'СуммаВыплатПоДопТарифу27-2-18'); 
  end loop; 
  for xt in 
    ( select rownum i, column_value x4 
        from XMLTable('/*/СуммаВыплатИвознагражденийПоДопТарифу' passing p_xdoc)) 
  loop 
    l_pmtb.extend(); 
    xt.i:=l_pmtb.last(); 
    select nvl(pmon,0), acode, x2money(suma1c), x2money(suma2c) 
      into l_pmtb(xt.i).pmon, l_pmtb(xt.i).acode 
         , l_pmtb(xt.i).suma1, l_pmtb(xt.i).suma2 
      from XMLTable('/' passing xt.x4 
         columns "PMON" number path 'Месяц' 
         , "ACODE" varchar2(15) path 'КодСпециальнойОценкиУсловийТруда' 
         , "SUMA1C" varchar2(15) path 'СуммаВыплатПоДопТарифу27-1' 
         , "SUMA2C" varchar2(15) path 'СуммаВыплатПоДопТарифу27-2-18'); 
  end loop; 
  return l_pmtb; 
end; 
-- Анализ. Заголовок формы. 
Function hdr_parse(p_xdoc xmltype) return hdr_tp 
as 
l_hdr hdr_tp; 
begin 
  select substr(ftype,1,3), lname, fname, sname, snils2num(snilsc) 
    , case when upper(fired)='УВОЛЕН' then 1 else 0 end 
    , x2money(nvl(isumc5,isumc)), x2money(fsumc), x2money(cisumc), x2money(cfsumc) 
-- период и корректируемый период формы из описи файла (пачки)  
--    , nvl(cpyear,cpyear3), nvl(cpquarter,0) 
    , substr(emptype,1,3), substr(contype,1,3) 
    into l_hdr.ftype, l_hdr.lname, l_hdr.fname, l_hdr.sname, l_hdr.snils 
      , l_hdr.fired 
      , l_hdr.isum, l_hdr.fsum, l_hdr.cisum, l_hdr.cfsum 
--      , l_hdr.cpyear, l_hdr.cpindex 
      , l_hdr.emptype, l_hdr.contype 
    from XMLTable('/' passing p_xdoc 
        columns "FTYPE" varchar2(100) path 'ТипСведений' 
       , "LNAME" varchar2(80) path 'ФИО/Фамилия' 
       , "FNAME" varchar2(80) path 'ФИО/Имя' 
       , "SNAME" varchar2(80) path 'ФИО/Отчество' 
       , "FIRED" varchar2(16) path 'СведенияОбУвольнении' 
       , "SNILSC" varchar2(100) path 'СтраховойНомер' 
       , "ISUMC" varchar2(15) path 'СуммаВзносовНаСтраховую/Начислено' 
       , "FSUMC" varchar2(15) path 'СуммаВзносовНаНакопительную/Начислено' 
       , "CISUMC" varchar2(15) path 'СуммаВзносовНаСтраховую/Уплачено' 
       , "CFSUMC" varchar2(15) path 'СуммаВзносовНаНакопительную/Уплачено' 
       , "ISUMC5" varchar2(15) path 'СуммаВзносовНаОПС' 
--       , "CPYEAR" number path 'КорректируемыйПериод/Год' 
--       , "CPYEAR3" number path 'КорректируемыйГод' 
--       , "CPQUARTER" number path 'КорректируемыйПериод/Квартал' 
       , "EMPTYPE" varchar2(10) path 'КодКатегории' 
       , "CONTYPE" varchar2(100) path 'ТипДоговора'); 
  return l_hdr; 
end; 
-- Определить вид (номер) формы по типу документа <ТипДокумента> 
Function dtype2fn(p_dtype varchar2, p_xdts varr_tp := c_xdts ) return number 
as 
begin 
  for i in 1..p_xdts.last loop 
    continue when p_xdts(i) is null; 
    if p_dtype like p_xdts(i) then return i; end if; 
  end loop; 
  raise_error(4); 
end; 
-- Анализ. Данные об организации, отчетном периоде, содержимом XML файла ПФР 
-- Формы ПФР 2010-2016гг
Function xpf6_info_parse(p_xml xmltype) return xml_info_tp 
as 
l_info xml_info_tp; 
l_rootname varchar2(400); 
begin 
-- Имя файла и программы генерации 
  select trim(xname), trim(xprogram), trim(xversion) 
    into l_info.xname, l_info.xprogram, l_info.xversion 
    from XMLTable('/ФайлПФР' passing p_xml 
        columns "XNAME" varchar2(200) PATH 'ИмяФайла' 
       ,"XPROGRAM" varchar2(200) PATH 'ЗаголовокФайла/ПрограммаПодготовкиДанных/НазваниеПрограммы' 
       ,"XVERSION" varchar2(200) PATH 'ЗаголовокФайла/ПрограммаПодготовкиДанных/Версия' 
    ); 
-- Вид (номер) формы 
  select rootname into l_rootname 
    from xmltable('for $node in /ФайлПФР/ПачкаВходящихДокументов/*[1] return <x><ROOTNAME>{name($node/.)}</ROOTNAME></x>' 
         passing p_xml 
         columns rootname varchar2(400)); 
  l_info.xfile.fn:=dtype2fn(l_rootname,c_xhds); 
-- Опись пачки документов 
  select substr(nvl(nvl(onames,oname),nvl(onames9,oname9)),1,50), pf_xml6.pfn2num(nvl(opfn,opfn9)) 
    , nvl(oinn,oinn9), nvl(okpp,okpp9) 
    , nvl(nvl(pcode,pcode9),0), nvl(nvl(nvl(pyear,pyear3),pyear9),0), deckn 
    , okved9 
    , xfcount, substr(ftype,1,3), cpcode, nvl(cpyear,cpyear3) 
    , substr(contype,1,3), emptype 
    into l_info.org.oname, l_info.org.opfn, l_info.org.oinn, l_info.org.okpp 
      , l_info.org.pindex, l_info.org.pyear, l_info.xfile.xid 
      , l_info.org.okved 
      , l_info.xfile.xfcount, l_info.xfile.ftype, l_info.xfile.cpindex, l_info.xfile.cpyear 
      , l_info.xfile.contype, l_info.xfile.emptype 
    from XMLTable('/ФайлПФР/ПачкаВходящихДокументов/*[1]' passing p_xml 
      columns "ONAME" varchar2(200) PATH 'СоставительПачки/НаименованиеОрганизации' 
      , "ONAMES" varchar2(200) PATH 'СоставительПачки/НаименованиеКраткое' 
      , "OPFN" varchar2(100) PATH 'СоставительПачки/РегистрационныйНомер' 
      , "OINN" number PATH 'СоставительПачки/НалоговыйНомер/ИНН' 
      , "OKPP" number PATH 'СоставительПачки/НалоговыйНомер/КПП' 
      , "ONAMES9" varchar2(200) PATH 'НаименованиеКраткое'    --РСВ-1 
      , "ONAME9" varchar2(200) PATH 'НаименованиеОрганизации' --РСВ-1 
      , "OPFN9" varchar2(200) PATH 'РегистрационныйНомерПФР'  --РСВ-1 
      , "OINN9" number PATH 'ИННсимвольный'       --РСВ-1 
      , "OKPP9" number PATH 'КПП'                 --РСВ-1 
      , "OKVED9" varchar2(16) PATH 'КодПоОКВЭД'   --РСВ-1 
      , "PYEAR9" number PATH 'КалендарныйГод'     --РСВ-1 
      , "PCODE9" number PATH 'КодОтчетногоПериода'--РСВ-1 
      , "PYEAR" number PATH 'ОтчетныйПериод/Год' 
      , "PCODE" number PATH 'ОтчетныйПериод/Квартал' 
      , "PYEAR3" number PATH 'ОтчетныйГод'        --СЗВ-6-3 
      , "DECKN" number PATH 'НомерПачки/Основной' 
      , "DTYPE" varchar2(512) PATH 'СоставДокументов/НаличиеДокументов/ТипДокумента' 
      , "XFCOUNT" number PATH 'СоставДокументов/НаличиеДокументов/Количество'           
      , "FTYPE" varchar2(200) PATH 'ТипСведений'           
      , "CONTYPE" varchar2(200) PATH 'ТипДоговора'           
      , "EMPTYPE" varchar2(200) PATH 'КодКатегории'           
      , "CPCODE" number PATH 'КорректируемыйОтчетныйПериод/Квартал'          
      , "CPYEAR" number PATH 'КорректируемыйОтчетныйПериод/Год'          
      , "CPYEAR3" number PATH 'КорректируемыйГод' --СЗВ-6-3          
    ); 
  l_info.org.sdeck := l_info.xfile.xid; 
  l_info.org.pindex:=case when l_info.xfile.fn=fn_szv3 then 4 
        else x2pindex(l_info.org.pindex,l_info.org.pyear) end; 
  l_info.xfile.cpindex:=case 
        when l_info.xfile.fn=fn_szv3 and l_info.xfile.cpyear is not null then 4 
        else x2pindex(l_info.xfile.cpindex,l_info.xfile.cpyear) end; 
  l_info.xfile.xkey:=l_info.xfile.fn||':'||l_info.xfile.ftype||':'|| 
      l_info.xfile.cpindex||':'||l_info.xfile.cpyear||':'|| 
      l_info.xfile.contype||':'||l_info.xfile.emptype; 
  return l_info; 
end;
--
Function xns7_info_parse(p_xml xmltype) return xml_info_tp
as
xml_info xml_info_tp;
begin
  return xml_info;
end;
--
Function xpf7_info_parse(p_xml xmltype) return xml_info_tp
as
xml_info xml_info_tp;
begin
  return xml_info;
end;
--
Function xinfo_parse(p_xml xmltype) return xml_info_tp
as
node_exists pls_integer;
begin
  select existsnode(p_xml,'/Файл/Документ/@КНД') into node_exists from dual;
  if node_exists = 1 then return xns7_info_parse(p_xml); end if;
  select existsnode(p_xml,'/ЭДПФР') into node_exists from dual;
  if node_exists = 1 then return xpf7_info_parse(p_xml); end if;
  select existsnode(p_xml,'/ФайлПФР') into node_exists from dual;
  if node_exists = 1 then return xpf6_info_parse(p_xml); end if;
  raise_error(4); -- не поддерживается
end;
--
Function file_info_get(p_xml CLOB) return xml_info_tp 
as 
begin 
  return xinfo_parse(xmltype(ns_remove(p_xml))); 
end; 
-- Анализ XML-файла  
Function parse(p_xml clob) return number 
as 
  l_xml xmltype:=xmltype(ns_remove(p_xml)); 
  l_info xml_info_tp; 
  l_xid number; 
  l_frm form_tp; 
begin 
  l_info:=xinfo_parse(l_xml); 
-- АДВ не поддерживается 
  if l_info.xfile.fn = fn_adv then raise_error(4); end if;  
-- проверить совпадение данных организации 
  if nvl(v_pack.org.opfn,l_info.org.opfn) <> l_info.org.opfn 
    or nvl(v_pack.org.oinn,l_info.org.oinn) <> l_info.org.oinn 
    or nvl(v_pack.org.okpp,l_info.org.okpp) <> l_info.org.okpp 
  then raise_error(2); end if; 
-- ... отчетных периодов? 
  if nvl(v_pack.org.pyear,l_info.org.pyear) <> l_info.org.pyear 
    or nvl(v_pack.org.pindex,l_info.org.pindex) <> l_info.org.pindex 
  then raise_error(1); end if; 
-- РСВ-1 2014г? 
  if l_info.xfile.fn = fn_rsv then  
      if l_info.org.pyear < 2014 then raise_error(4); end if; 
      return rsv_parse(l_xml); 
  end if; 
-- проверка на наличие пачки, уже загружена - исключение 
  if v_pack.files.exists(l_info.xfile.xid) then raise_error(4); end if; 
  l_xid := l_info.xfile.xid; 
--  l_xid:=case when v_pack.files.count=0 then 1 else v_pack.files.last+1 end; 
--  l_info.xfile.xid:=l_xid; 
  v_pack.files(l_xid):=l_info.xfile; 
-- Формы СЗВ-6-1,2,3,4 или СЗВ-РСВ 
  for xt in 
    ( select rownum, column_value as x 
        from XMLTable('/ФайлПФР/ПачкаВходящихДокументов/*' passing l_xml ) ) 
  loop 
-- пропустим опись пачки      
    continue when xt.rownum=1; 
-- очистить форму 
    form_clear(l_frm); 
-- анализ и инициализация заголовка формы 
    l_frm.hdr:=hdr_parse(xt.x); 
    l_frm.hdr.fn:=l_info.xfile.fn; 
    l_frm.hdr.xid:=l_xid; 
    l_frm.hdr.fid:=case when v_pack.forms.count=0 then 1 else v_pack.forms.last+1 end ; 
    l_frm.hdr.ftype:=l_info.xfile.ftype; 
    l_frm.hdr.cpindex:=l_info.xfile.cpindex; 
    l_frm.hdr.cpyear:=l_info.xfile.cpyear; 
-- периоды работы формы 
    l_frm.periods:=pd_parse(xt.x); 
    for i in 1..l_frm.periods.count 
      loop l_frm.periods(i).fid:=l_frm.hdr.fid; end loop; 
-- доходы/базы 
    l_frm.incomes:=inc_parse(xt.x); 
    for i in 1..l_frm.incomes.count 
    loop 
      l_frm.incomes(i).fid:=l_frm.hdr.fid; 
      if nvl(l_frm.incomes(i).pmon,0) between 1 and 3 
          and nvl(l_frm.hdr.cpindex,l_info.org.pindex) > 1 then 
        l_frm.incomes(i).pmon:=(nvl(l_frm.hdr.cpindex,l_info.org.pindex)-1)*3 
          + l_frm.incomes(i).pmon; 
      end if; 
    end loop; 
-- выплаты по доптарифам 
    l_frm.payments:=pmt_parse(xt.x); 
    for i in 1..l_frm.payments.count 
    loop 
      l_frm.payments(i).fid:=l_frm.hdr.fid; 
      if nvl(l_frm.payments(i).pmon,0) between 1 and 3 
          and nvl(l_frm.hdr.cpindex,l_info.org.pindex) > 1 then 
        l_frm.payments(i).pmon:=(nvl(l_frm.hdr.cpindex,l_info.org.pindex)-1)*3 
          + l_frm.payments(i).pmon; 
      end if; 
    end loop; 
-- сведения о корректировках 
    l_frm.corrs:=cor_parse(xt.x); 
    for i in 1..l_frm.corrs.count 
      loop l_frm.corrs(i).fid:=l_frm.hdr.fid; end loop; 
    v_pack.forms(l_frm.hdr.fid):=l_frm; 
  end loop; 
-- вернуть id XML-файла 
  return l_xid; 
end; 
/* 
   ГЕНЕРАЦИЯ XML-ФАЙЛОВ ПФР   
*/ 
-- Сформировать XML-узел при условии 
Function xnode(p_name varchar2, p_value varchar2, p_cond boolean := true) return varchar2 
as 
begin 
  if not p_cond then return ''; end if; 
  if p_name is null then return p_value; end if; 
  return '<'||p_name|| 
    case when p_value is null then '/>' 
      else '>'||trim(p_value)||'</'||p_name||'>' 
    end; 
end; 
-- Генерация. Сведения о корректировках (СЗВ-РСВ) 
Procedure corrs_append(p_cxml in out nocopy CLOB, p_fid number) 
as 
l_crc CLOB; 
begin 
  if v_pack.forms(p_fid).hdr.fn <> fn_szvr  
    or v_pack.forms(p_fid).hdr.ftype <> 'ИСХ' then return; end if; 
  for ft in  
    ( select rownum i, st.* from table(corrs_tbl(p_fid)) st) 
  loop 
    l_crc:=xnode('СведенияОкорректировках', 
      xnode('НомерСтроки',ft.i)|| 
      xnode('ТипСтроки',case when nvl(ft.cpyear,0)=0 then 'ИТОГ' else 'МЕСЦ' end)|| 
      xnode('Квартал',pindex2x(ft.cpindex,ft.cpyear),nvl(ft.cpyear,0)>0)|| 
      xnode('Год',ft.cpyear,nvl(ft.cpyear,0)>0)|| 
      xnode('СуммаДоначисленныхВзносовОПС',nvlmoney2x(ft.dpsum) 
          ,nvl(ft.cpyear,0)=0 or ft.cpyear>=2014)|| 
      xnode('СуммаДоначисленныхВзносовНаСтраховую',nvlmoney2x(ft.disum) 
          ,nvl(ft.cpyear,0)=0 or ft.cpyear<2014)|| 
      xnode('СуммаДоначисленныхВзносовНаНакопительную',nvlmoney2x(ft.dfsum) 
          ,nvl(ft.cpyear,0)=0 or ft.cpyear<2014) 
    ); 
    dbms_lob.copy(p_cxml,l_crc,dbms_lob.getlength(l_crc),dbms_lob.getlength(p_cxml)+1,1); 
  end loop; 
end; 
-- Генерация. Сведения о дополнительных выплатах 
Procedure payments_append(p_cxml in out nocopy CLOB, p_fid number) 
as 
l_pmrc pmt_tp; 
l_crc CLOB; 
l_acode varchar2(16):='null'; 
l_ai number:=-10; 
l_emon number:=nvl(v_pack.forms(p_fid).hdr.cpindex,v_pack.org.pindex)*3; 
begin 
  if v_pack.forms(p_fid).payments.count = 0 
    or v_pack.forms(p_fid).hdr.fn < fn_szv4  
    or v_pack.forms(p_fid).hdr.ftype = 'ОТМ' then return; end if; 
/* 
i: выбрать месяцы периода, группировать по acode 
*/ 
  for pt in 
    (select rownum i, tb.* from table (payments_tbl(p_fid)) tb 
       where nvl(pmon,0) in (0,l_emon,l_emon-1,l_emon-2) 
       order by acode, nvl(pmon,0)) 
  loop 
    if l_acode <> nvl(pt.acode,'acode') then -- изменился код доп. тарифа? 
      l_acode:=nvl(pt.acode,'acode');        -- сменим текущий 
      l_ai:=l_ai+10;                         -- приращение кода строки 
    end if; 
    l_crc:=''|| 
      case v_pack.forms(p_fid).hdr.fn  
        when fn_szv4 then  
          xnode('СуммаВыплатИвознагражденийПоДопТарифу', 
            xnode('ТипСтроки',case nvl(pt.pmon,0) when 0 then 'ИТОГ' else 'МЕСЦ' end)|| 
            xnode('Месяц',pt.pmon,nvl(pt.pmon,0) > 0)|| 
            xnode('СуммаВыплатПоДопТарифу27-1',money2x(nvl(pt.suma1,0)))|| 
            xnode('СуммаВыплатПоДопТарифу27-2-18',money2x(nvl(pt.suma2,0))) 
          ,nvl(pt.suma1,0)+nvl(pt.suma2,0)>0) 
        when fn_szvr then 
          xnode('СведенияОсуммеВыплатИвознагражденийПоДопТарифу', 
            xnode('НомерСтроки',pt.i)|| 
            xnode('ТипСтроки',case nvl(pt.pmon,0) when 0 then 'ИТОГ' else 'МЕСЦ' end)|| 
            xnode('Месяц',pt.pmon,nvl(pt.pmon,0) > 0)|| 
            xnode('КодСтроки',700+l_ai,nvl(pt.pmon,0)=0) || 
            xnode('КодСтроки',700+l_ai+(pt.pmon-(l_emon-3)),nvl(pt.pmon,0)>0)|| 
            xnode('КодСпециальнойОценкиУсловийТруда',pt.acode)|| 
            xnode('СуммаВыплатПоДопТарифу27-1',nvlmoney2x(pt.suma1))|| 
            xnode('СуммаВыплатПоДопТарифу27-2-18',nvlmoney2x(pt.suma2)) 
          ,nvl(pt.suma1,0)+nvl(pt.suma2,0)>0) 
        else '' end; 
    continue when l_crc is null; 
    dbms_lob.copy(p_cxml,l_crc,dbms_lob.getlength(l_crc),dbms_lob.getlength(p_cxml)+1,1); 
  end loop; 
end; 
-- Генерация. Сведения о доходах/базах 
Procedure incomes_append(p_cxml in out nocopy CLOB, p_fid number) 
as 
l_inrc inc_tp; 
l_crc CLOB; 
l_emptype varchar2(16):='null'; 
l_ei number:=-10; 
l_emon number:=nvl(v_pack.forms(p_fid).hdr.cpindex,v_pack.org.pindex)*3; 
l_outsums boolean :=true; 
begin 
  if v_pack.forms(p_fid).hdr.fn < fn_szv4 then return; end if; 
  if v_pack.forms(p_fid).incomes.count = 0 then 
    select p_fid,0,'НР',null,null,null,null -- добавить пустую запись 
      bulk collect into v_pack.forms(p_fid).incomes from dual ; 
  end if; 
  l_outsums := upper(v_pack.forms(p_fid).hdr.ftype) in ('ИСХ','КОР'); 
-- выбрать месяцы периода, группировать по emptype 
  for it in  
    (select rownum i, tb.* from table (incomes_tbl(p_fid)) tb 
       where nvl(pmon,0) in (0,l_emon,l_emon-1,l_emon-2) 
       order by emptype, nvl(pmon,0)) 
  loop 
    if l_emptype <> nvl(it.emptype,'emptype') then -- изменилась категория? 
      l_emptype:=nvl(it.emptype,'emptype');        -- категория ЗЛ 
      l_ei:=l_ei+10;                               -- приращение кода строки 
    end if; 
    case v_pack.forms(p_fid).hdr.fn 
      when fn_szv4 then 
        l_crc:=xnode('СуммаВыплатИвознагражденийВпользуЗЛ', 
          xnode('ТипСтроки',case when nvl(it.pmon,0)=0 then 'ИТОГ' else 'МЕСЦ' end) || 
          xnode('Месяц',it.pmon,nvl(it.pmon,0)>0) || 
          xnode('СуммаВыплатВсего',money2x(it.sumt)) || 
          xnode('СуммаВыплатНачисленыСтраховыеВзносыНеПревышающие',money2x(it.sumb))|| 
          xnode('СуммаВыплатНачисленыСтраховыеВзносыПревышающие',money2x(it.sumo)) 
        ); 
      when fn_szvr then 
        l_crc:=xnode('СведенияОсуммеВыплатИвознагражденийВпользуЗЛ', 
          xnode('НомерСтроки',it.i)|| 
          xnode('ТипСтроки',case when nvl(it.pmon,0)=0 then 'ИТОГ' else 'МЕСЦ' end) || 
          xnode('Месяц',it.pmon,nvl(it.pmon,0)>0) || 
          xnode('КодСтроки',400+l_ei,nvl(it.pmon,0)=0) || 
          xnode('КодСтроки',400+l_ei+(it.pmon-(l_emon-3)),nvl(it.pmon,0)>0) || 
          xnode('КодКатегории',it.emptype) || 
          xnode('СуммаВыплатИныхВознаграждений',nvlmoney2x(it.sumt),l_outsums) || 
          xnode('НеПревышающиеВсего',nvlmoney2x(it.sumb),l_outsums)|| 
          xnode('НеПревышающиеПоДоговорам',nvlmoney2x(it.sumbg),l_outsums)|| 
          xnode('ПревышающиеПредельную',nvlmoney2x(it.sumo),l_outsums) 
        ); 
      else null; 
    end case; 
    dbms_lob.copy(p_cxml,l_crc,dbms_lob.getlength(l_crc),dbms_lob.getlength(p_cxml)+1,1); 
  end loop; 
  
end; 
-- Генерация. Сведения о периодах работы 
Procedure periods_append(p_cxml in out nocopy CLOB,p_fid number) 
as 
l_pdrc pd_tp; 
l_crc CLOB; 
l_aspec APEX_APPLICATION_GLOBAL.VC_ARR2; 
Function spec_get 
( p_aspec APEX_APPLICATION_GLOBAL.VC_ARR2 
, p_index number) return varchar2 
is 
begin 
    return p_aspec(p_index); 
exception 
    when others then return null; 
end; 
Function hmmd2x 
( p_aspec APEX_APPLICATION_GLOBAL.VC_ARR2 
, p_index number) return varchar2 
is 
begin 
  return case  
    when (spec_get(p_aspec,p_index)||spec_get(p_aspec,p_index+1)) is not null then 
      xnode('ВыработкаВчасах', 
        xnode('Часы',spec_get(p_aspec,p_index))|| 
        xnode('Минуты',spec_get(p_aspec,p_index+1)) 
      ) 
    else 
      xnode('ВыработкаКалендарная', 
        xnode('ВсеМесяцы',spec_get(p_aspec,p_index+2))|| 
        xnode('ВсеДни',spec_get(p_aspec,p_index+3)) 
     ) 
    end; 
end; 
begin 
  if v_pack.forms(p_fid).periods.count=0  
    or upper(v_pack.forms(p_fid).hdr.ftype)='ОТМ' then return; end if; 
  dbms_lob.createtemporary(l_crc, true, dbms_lob.session);   
  for i in v_pack.forms(p_fid).periods.first..v_pack.forms(p_fid).periods.last loop 
    continue when not v_pack.forms(p_fid).periods.exists(i); 
    l_pdrc:=v_pack.forms(p_fid).periods(i); 
    l_aspec:=APEX_UTIL.STRING_TO_TABLE(l_pdrc.specs);  
    l_crc:=xnode('СтажевыйПериод', 
      xnode('НомерСтроки',l_pdrc.nn)|| 
      xnode('ДатаНачалаПериода',date2x(l_pdrc.sdate))|| 
      xnode('ДатаКонцаПериода',date2x(l_pdrc.edate))|| 
      case  
        when trim(l_pdrc.terr||l_pdrc.dd 
            ||spec_get(l_aspec,1)||spec_get(l_aspec,3)||spec_get(l_aspec,8)) is not null 
        then 
          xnode('КоличествоЛьготныхСоставляющих',1) || 
          xnode('ЛьготныйСтаж', 
            xnode('НомерСтроки',1)|| 
            xnode('ОсобенностиУчета', 
              xnode('ТерриториальныеУсловия', 
                  xnode('ОснованиеТУ',l_pdrc.terr)|| 
                  xnode('Коэффициент',money2x(l_pdrc.terrc),l_pdrc.terrc is not null) 
                , l_pdrc.terr is not null)|| 
              xnode('ОсобыеУсловияТруда', 
                  xnode('ОснованиеОУТ',spec_get(l_aspec,1))|| 
                  xnode('ПозицияСписка',spec_get(l_aspec,2)) 
                , spec_get(l_aspec,1) is not null)|| 
              xnode('ИсчисляемыйСтаж', 
                  xnode('ОснованиеИС', spec_get(l_aspec,3))|| 
                  hmmd2x(l_aspec,4) 
                , spec_get(l_aspec,3) is not null)|| 
              xnode('ДекретДети',l_pdrc.dd)|| 
              xnode('ВыслугаЛет', 
                  xnode('ОснованиеВЛ',spec_get(l_aspec,8))|| 
                  hmmd2x(l_aspec,9)|| 
                  xnode('ДоляСтавки',money2x(spec_get(l_aspec,13))) 
                , spec_get(l_aspec,8) is not null) 
            ) 
          ) 
        else ''   
      end 
    ); 
    dbms_lob.copy(p_cxml,l_crc,dbms_lob.getlength(l_crc),dbms_lob.getlength(p_cxml)+1,1); 
  end loop; 
  dbms_lob.freetemporary(l_crc); 
end; 
-- Генерация. Сведения об организации 
Function org2x(p_inhdr boolean:=true) return varchar2 
as 
 l_cxml varchar2(4000); 
begin 
  l_cxml:=xnode('РегистрационныйНомер',num2pfn(v_pack.org.opfn),not p_inhdr)|| 
          xnode('НаименованиеКраткое',upper(substr(v_pack.org.oname,1,50)),not p_inhdr)|| 
          xnode('НалоговыйНомер', 
             xnode('ИНН',trim(to_char(v_pack.org.oinn,'0000000000')))|| 
             xnode('КПП', trim(to_char(v_pack.org.okpp,'000000000'))) 
          )|| 
          xnode('НаименованиеКраткое',upper(substr(v_pack.org.oname,1,50)),p_inhdr)|| 
          xnode('РегистрационныйНомер',num2pfn(v_pack.org.opfn),p_inhdr); 
   return l_cxml; 
end; 
-- Генерация. Сведения об отчетном и корректируемом периоде 
Function rpd2x(p_xid number) return varchar2 
as 
 l_cxml varchar2(4000); 
begin 
  l_cxml:=  
     xnode('ОтчетныйПериод', 
        xnode('Квартал',pindex2x(v_pack.org.pindex,v_pack.org.pyear))|| 
        xnode('Год', v_pack.org.pyear) 
     )|| 
     xnode('КорректируемыйОтчетныйПериод', 
        xnode('Квартал',pindex2x(v_pack.files(p_xid).cpindex,v_pack.files(p_xid).cpyear))|| 
        xnode('Год',v_pack.files(p_xid).cpyear) 
     , v_pack.files(p_xid).ftype <> 'ИСХ'); 
   return l_cxml; 
end; 
-- Генерация. Список форм файла 
Procedure docs_append(p_fxml in out nocopy CLOB, p_xid number) 
as 
l_form form_tp; 
l_cxml CLOB; 
begin 
  dbms_lob.createtemporary(l_cxml, true, dbms_lob.session);   
  for ft in (select rownum i, ftbl.* from table(pf_xml6.forms_tbl()) ftbl where xid=p_xid) 
  loop 
    l_form:=v_pack.forms(ft.fid); 
    l_cxml:='<'||c_xdts(l_form.hdr.fn)||'>'|| 
        xnode('НомерВпачке',ft.i+1)|| 
        xnode('ВидФормы',abbr2x(l_form.hdr.fn),l_form.hdr.fn in (fn_szv1,fn_szv2))|| 
        xnode('ТипСведений',abbr2x(l_form.hdr.ftype))|| 
        xnode('РегистрационныйНомер',num2pfn(v_pack.org.opfn),l_form.hdr.fn = fn_szvr)|| 
        xnode(null,org2x(false),l_form.hdr.fn <> fn_szvr)|| 
        xnode('КодКатегории',l_form.hdr.emptype 
            ,l_form.hdr.fn between fn_szv1 and fn_szv4)|| 
        xnode(null,rpd2x(p_xid),l_form.hdr.fn<>fn_szvr)|| 
        xnode('СтраховойНомер',num2snils(l_form.hdr.snils))|| 
        xnode('ФИО', 
            xnode('Фамилия',l_form.hdr.lname)|| 
            xnode('Имя',l_form.hdr.fname)|| 
            xnode('Отчество',l_form.hdr.sname) 
        )|| 
        xnode('СведенияОбУвольнении','УВОЛЕН' 
            , l_form.hdr.fired=1 and l_form.hdr.fn=fn_szvr )|| 
        xnode(null,rpd2x(p_xid),l_form.hdr.fn=fn_szvr)|| 
--        xnode('РегистрационныйНомерКорректируемогоПериода' 
--            , num2pfn(nvl(l_form.hdr.copfn,v_pack.org.opfn)) 
--        , l_form.hdr.fn in (fn_szv4,fn_szvr) and l_form.hdr.ftype<>'ИСХ')|| 
        xnode('ТипДоговора',abbr2x(l_form.hdr.contype),l_form.hdr.fn in (fn_szv3,fn_szv4)); 
    incomes_append(l_cxml, l_form.hdr.fid); 
    dbms_lob.append(l_cxml 
        , case l_form.hdr.fn 
          when fn_szvr then xnode('СуммаВзносовНаОПС',nvlmoney2x(l_form.hdr.isum)) 
          when fn_szv3 then ''  -- exception 
          else 
            xnode('СуммаВзносовНаСтраховую', 
              xnode('Начислено',nvlmoney2x(l_form.hdr.isum))|| 
              xnode('Уплачено',nvlmoney2x(nvl(l_form.hdr.cisum,l_form.hdr.isum))) 
            )|| 
            xnode('СуммаВзносовНаНакопительную', 
              xnode('Начислено',nvlmoney2x(l_form.hdr.fsum))|| 
              xnode('Уплачено',nvlmoney2x(nvl(l_form.hdr.cfsum,l_form.hdr.fsum))) 
            ) 
          end || 
       xnode('ДатаЗаполнения',date2x(sysdate),l_form.hdr.fn<fn_szvr) 
    ); 
    corrs_append(l_cxml, l_form.hdr.fid); 
    payments_append(l_cxml, l_form.hdr.fid); 
    periods_append(l_cxml, l_form.hdr.fid); 
    dbms_lob.append(l_cxml,xnode('ДатаЗаполнения',date2x(sysdate),l_form.hdr.fn=fn_szvr) 
        ||'</'||c_xdts(l_form.hdr.fn)||'>'); 
    dbms_lob.copy(p_fxml,l_cxml,dbms_lob.getlength(l_cxml),dbms_lob.getlength(p_fxml)+1,1); 
  end loop; 
  dbms_lob.freetemporary(l_cxml); 
end; 
-- Генерация. Расчет сумм по формам файла 
Function xtotal_calc(p_xid number) return xtotal_tp 
as 
l_xtt xtotal_tp; 
l_emon number:=nvl(v_pack.files(p_xid).cpindex,v_pack.org.pindex)*3; 
l_smon number:=l_emon-2; 
begin 
/* 
  select '' xname 
    , count(ft.fid), sum(nvl(ft.isum,0)) isum, sum(nvl(ft.fsum,0)) fsum 
    , sum(nvl(ft.cisum,0)) cisum, sum(nvl(ft.cfsum,0)) cfsum 
    , sum(it.sumt) sumt, sum(it.sumb) sumb, sum(it.sumo) sumo 
    into l_xtt 
    from  
      (select fid, isum, fsum, nvl(cisum, isum) cisum, nvl(cfsum, fsum) cfsum  
         from table(pf_xml6.forms_tbl) where xid=p_xid) ft 
      left join  
      (select fid 
         , sum(nvl(sumt,0)) sumt, sum(nvl(sumb,0)) sumb, sum(nvl(sumo,0)) sumo 
         from table(pf_xml6.incomes_tbl) where pmon between l_smon and l_emon 
         group by fid) it  
      on ft.fid=it.fid; 
*/   
  for ft in 
    (select * from table(forms_tbl) where xid=p_xid) 
  loop 
    l_xtt.fcount:=l_xtt.fcount+1; 
    l_xtt.isum:=l_xtt.isum+nvl(ft.isum,0); 
    l_xtt.fsum:=l_xtt.fsum+nvl(ft.fsum,0); 
    l_xtt.cisum:=l_xtt.cisum+nvl(ft.cisum,nvl(ft.isum,0)); 
    l_xtt.cfsum:=l_xtt.cfsum+nvl(ft.cfsum,nvl(ft.fsum,0)); 
    continue when v_pack.forms(ft.fid).incomes.count=0 ; 
    for i in v_pack.forms(ft.fid).incomes.first..v_pack.forms(ft.fid).incomes.last 
    loop 
      continue when not v_pack.forms(ft.fid).incomes.exists(i); 
      if v_pack.forms(ft.fid).incomes(i).pmon between l_smon and l_emon then 
        l_xtt.sumt:=l_xtt.sumt+nvl(v_pack.forms(ft.fid).incomes(i).sumt,0); 
        l_xtt.sumb:=l_xtt.sumb+nvl(v_pack.forms(ft.fid).incomes(i).sumb,0); 
        l_xtt.sumo:=l_xtt.sumo+nvl(v_pack.forms(ft.fid).incomes(i).sumo,0); 
      end if; 
    end loop; 
  end loop; 
  return l_xtt; 
end; 
-- Генерация XML-файла     
Function generate(p_xid number:=0) return clob 
as 
l_cxml CLOB; 
l_fn number(1); 
l_xttl xtotal_tp; 
begin 
  if p_xid = 0 then return rsv_generate; end if; 
  l_fn:=v_pack.files(p_xid).fn; 
  if l_fn=fn_szv3 then raise_error(4); end if; -- формы СЗВ-6-3 не генерируются 
  l_xttl:=xtotal_calc(p_xid); 
  dbms_lob.createtemporary(l_cxml, true, dbms_lob.session); 
  if l_xttl.fcount=0 then return l_cxml; end if; 
  l_cxml:='<?xml version="1.0" encoding="Windows-1251" ?><ФайлПФР xmlns="http://schema.pfr.ru">'|| 
    xnode('ИмяФайла', file_name_make(p_xid))|| 
    xnode('ЗаголовокФайла', 
        xnode('ВерсияФормата','07.00')|| 
        xnode('ТипФайла','ВНЕШНИЙ')|| 
        xnode('ПрограммаПодготовкиДанных', 
            xnode('НазваниеПрограммы',upper(c_program))|| 
            xnode('Версия',upper(c_version)) 
        )|| 
        xnode('ИсточникДанных','СТРАХОВАТЕЛЬ') 
    )||'<ПачкаВходящихДокументов Окружение="В составе файла" Стадия="До обработки">'|| 
    xnode(c_xhds(l_fn), 
        xnode('НомерВпачке',1)|| 
        xnode('ТипВходящейОписи','ОПИСЬ ПАЧКИ')|| 
        xnode('СоставительПачки', org2x)|| 
        xnode('НомерПачки', 
            xnode('Основной',trim(to_char(p_xid,'00000'))) 
        )|| 
        xnode('СоставДокументов', 
            xnode('Количество',1)|| 
            xnode('НаличиеДокументов', 
                xnode('ТипДокумента', c_xdts(l_fn))|| 
                xnode('Количество',trim(l_xttl.fcount)) 
            ) 
        )|| 
        xnode('ДатаСоставления',date2x(sysdate))|| 
        xnode('ТипСведений',abbr2x(v_pack.files(p_xid).ftype))|| 
        xnode('КодКатегории',v_pack.files(p_xid).emptype,l_fn between fn_szv1 and fn_szv4)|| 
        rpd2x(p_xid)|| -- отчетный и корректируемый периоды 
        xnode('ТипДоговора',abbr2x(v_pack.files(p_xid).contype),l_fn in (fn_szv3,fn_szv4))|| 
        xnode('СуммаВыплатИвознагражденийВпользуЗЛ', 
            xnode('ТипСтроки','ИТОГ')|| 
            xnode('СуммаВыплатВсего', money2x(l_xttl.sumt))|| 
            xnode('СуммаВыплатНачисленыСтраховыеВзносыНеПревышающие' 
                , money2x(l_xttl.sumb))|| 
            xnode('СуммаВыплатНачисленыСтраховыеВзносыПревышающие' 
                ,money2x(l_xttl.sumo)) 
        , l_fn=fn_szv4)|| 
        xnode('СуммаВзносовНаСтраховую', 
            xnode('Начислено',nvlmoney2x(l_xttl.isum))|| 
            xnode('Уплачено',nvlmoney2x(nvl(l_xttl.cisum,l_xttl.isum))) 
        , l_fn between fn_szv1 and fn_szv4)|| 
        xnode('СуммаВзносовНаНакопительную', 
            xnode('Начислено',nvlmoney2x(l_xttl.fsum))|| 
            xnode('Уплачено',nvlmoney2x(nvl(l_xttl.cfsum,l_xttl.fsum))) 
        , l_fn between fn_szv1 and fn_szv4)|| 
        xnode('БазаДляНачисленияСтраховыхВзносовНеПревышающаяПредельную' 
            ,nvlmoney2x(l_xttl.sumb),l_fn=fn_szvr)|| 
        xnode('СтраховыхВзносовОПС',nvlmoney2x(l_xttl.isum),l_fn=fn_szvr) 
    ); 
  docs_append(l_cxml, p_xid); 
  dbms_lob.append(l_cxml,'</ПачкаВходящихДокументов></ФайлПФР>'); 
  return l_cxml; 
end; 
/* 
   Генерация РСВ-1 
*/ 
-- Генерация РСВ-1. Раздел 4 
Procedure rsv_part4_append(p_cxml in out nocopy CLOB) 
as 
l_p4tag varchar2(200):= 
  case when (v_pack.org.pyear*10 + v_pack.org.pindex) < 20152 
    then 'Раздел4СуммыДоначисленныхСтраховыхВзносов2014' 
    else 'Раздел4' 
  end; 
Function part4_common(p_row number) return varchar2 
as 
begin 
  return 
    xnode('СуммаДоначисленныхВзносовОПС2014всего', nvlmoney2x(part_value_get(part4_name,p_row,6)))|| 
    xnode('СуммаДоначисленныхВзносовОПС2014превыщающие', nvlmoney2x(part_value_get(part4_name,p_row,7)))|| 
    xnode('СуммаДоначисленныхВзносовНаСтраховуюВсего', nvlmoney2x(part_value_get(part4_name,p_row,8)))|| 
    xnode('СуммаДоначисленныхВзносовНаСтраховуюПревышающие', nvlmoney2x(part_value_get(part4_name,p_row,9)))|| 
    xnode('СуммаДоначисленныхВзносовНаНакопительную', nvlmoney2x(part_value_get(part4_name,p_row,10)))|| 
    xnode('СтраховыхДоначисленныхВзносовПоДопТарифуЧ1', nvlmoney2x(part_value_get(part4_name,p_row,11)))|| 
    xnode('СтраховыхДоначисленныхВзносовПоДопТарифуЧ2', nvlmoney2x(part_value_get(part4_name,p_row,12)))|| 
    xnode('СтраховыхДоначисленныхВзносовПоДопТарифуЧ2_1', nvlmoney2x(part_value_get(part4_name,p_row,13)))|| 
    xnode('СтраховыеВзносыОМС', nvlmoney2x(part_value_get(part4_name,p_row,14))); 
end; 
begin 
  if not v_parts.exists(part4_name) then return; end if; 
  dbms_lob.append(p_cxml,'<'||l_p4tag||'>'); 
  for i in 1..v_parts(part4_name).last loop 
    continue when not v_parts(part4_name).exists(i); 
-- СуммаДоначисленныхВзносовЗаПериодНачинаяС2014 
    dbms_lob.append(p_cxml, xnode('СуммаДоначисленныхВзносовЗаПериодНачинаяС2014', 
        xnode('НомерПП',part_value_get(part4_name,i,1))|| 
        xnode('ОснованиеДляДоначисления',part_value_get(part4_name,i,2))|| 
        xnode('КодОснованияДляДопТарифа',part_value_get(part4_name,i,3) 
              ,part_value_get(part4_name,i,3) is not null)|| 
        xnode('Год',part_value_get(part4_name,i,4))|| 
        xnode('Месяц',part_value_get(part4_name,i,5))|| 
        part4_common(i) 
    ));     
  end loop; 
-- ИтогоДоначисленоНачинаяС2014 
  dbms_lob.append(p_cxml, xnode('ИтогоДоначисленоНачинаяС2014', part4_common(0))|| 
      '</'||l_p4tag||'>'); 
  return; 
end; 
-- Генерация РСВ-1. Разделы 2.5.1, 2.5.2    
Procedure rsv_part25_append(p_cxml in out nocopy CLOB) 
as 
l_p25c varchar2(32767); 
begin 
  dbms_lob.append(p_cxml,'<Раздел_2_5>'); 
  if not v_parts.exists(part251_name) then return; end if; 
  for i in 1..v_parts(part251_name).last loop 
    continue when not v_parts(part251_name).exists(i); 
    l_p25c:=l_p25c|| 
         xnode('СведенияОпачкеИсходных', 
              xnode('НомерПП',part_value_get(part251_name,i,1))|| 
              xnode('БазаДляНачисленияСтраховыхВзносовНеПревышающаяПредельную' 
                  ,nvlmoney2x(part_value_get(part251_name,i,2)))|| 
              xnode('СтраховыхВзносовОПС',nvlmoney2x(part_value_get(part251_name,i,3)))|| 
              xnode('КоличествоЗЛвПачке',part_value_get(part251_name,i,4))|| 
              xnode('ИмяФайла',part_value_get(part251_name,i,5))); 
  end loop; 
-- итоги в строке с номером 0 
  dbms_lob.append(p_cxml, 
    xnode('ПереченьПачекИсходныхСведенийПУ', 
        xnode('КоличествоПачек',v_parts(part251_name).count-1)|| 
        xnode(null,l_p25c)|| 
        xnode('ИтогоСведенияПоПачкам', 
            xnode('БазаДляНачисленияСтраховыхВзносовНеПревышающаяПредельную' 
                , nvlmoney2x(part_value_get(part251_name,0,2)))|| 
            xnode('СтраховыхВзносовОПС', nvlmoney2x(part_value_get(part251_name,0,3)))|| 
            xnode('КоличествоЗЛвПачке', part_value_get(part251_name,0,4))) 
  )); 
  l_p25c:=''; 
  if v_parts.exists(part252_name) then 
    for i in 1..v_parts(part252_name).last loop 
      continue when not v_parts(part252_name).exists(i); 
      l_p25c:=l_p25c|| 
          xnode('СведенияОпачкеКорректирующих', 
            xnode('НомерПП',part_value_get(part252_name,i,1))|| 
            xnode('КорректируемыйОтчетныйПериод', 
                xnode('Квартал' 
                  ,pindex2x(part_value_get(part252_name,i,2),part_value_get(part252_name,i,3)))|| 
                xnode('Год',part_value_get(part252_name,i,3)))|| 
            xnode('ДоначисленоСтраховыхВзносовОПС', 
                nvlmoney2x(part_value_get(part252_name,i,4)) 
                ,part_value_get(part252_name,i,3)>=2014)|| 
            xnode('ДоначисленоНаСтраховуюЧасть', 
                nvlmoney2x(part_value_get(part252_name,i,5)) 
                ,part_value_get(part252_name,i,3)<2014)|| 
            xnode('ДоначисленоНаНакопительнуюЧасть', 
                nvlmoney2x(part_value_get(part252_name,i,6)) 
                ,part_value_get(part252_name,i,3)<2014)|| 
            xnode('КоличествоЗЛвПачке',part_value_get(part252_name,i,7))|| 
            xnode('ИмяФайла',trim(part_value_get(part252_name,i,8)))); 
    end loop; 
    if l_p25c is not null then 
      dbms_lob.append(p_cxml, 
        xnode('ПереченьПачекКорректирующихСведенийПУ', 
          xnode('КоличествоПачек',v_parts(part252_name).count-1)|| 
          xnode(null,l_p25c)|| 
          xnode('ИтогоСведенияПоПачкамКорректирующих', 
            xnode('ДоначисленоСтраховыхВзносовОПС' 
                , nvlmoney2x(part_value_get(part252_name,0,4)))|| 
            xnode('ДоначисленоНаСтраховуюЧасть' 
                , nvlmoney2x(part_value_get(part252_name,0,5)))|| 
            xnode('ДоначисленоНаНакопительнуюЧасть' 
                , nvlmoney2x(part_value_get(part252_name,0,6)))|| 
            xnode('КоличествоЗЛвПачке',part_value_get(part252_name,0,7))) 
      )); 
    end if; 
  end if; 
  dbms_lob.append(p_cxml,'</Раздел_2_5>'); 
  return; 
end; 
-- Генерация РСВ-1. Раздел 2.1 
Procedure rsv_part21_append(p_cxml in out nocopy CLOB) 
as 
  l_p21tag constant varchar2(200):='Раздел_2_1'; 
Function part21_blk(p_scode number, p_part varchar2) return varchar2 
as 
begin 
  return 
    xnode('КодСтроки',p_scode)|| 
    case when (p_scode in (207,208))  
         or ((v_pack.org.pyear*10 + v_pack.org.pindex) > 20151 and p_scode=215) 
    then 
       xnode('КоличествоЗЛ_Всего',part_value_get(p_part,p_scode,3))|| 
       xnode('КоличествоЗЛ_1месяц',part_value_get(p_part,p_scode,4))|| 
       xnode('КоличествоЗЛ_2месяц',part_value_get(p_part,p_scode,5))|| 
       xnode('КоличествоЗЛ_3месяц',part_value_get(p_part,p_scode,6)) 
    else 
       xnode('РасчетСумм', 
          xnode('СуммаВсегоСначалаРасчетногоПериода',nvlmoney2x(part_value_get(p_part,p_scode,3)))|| 
          xnode('СуммаПоследние1месяц',nvlmoney2x(part_value_get(p_part,p_scode,4)))|| 
          xnode('СуммаПоследние2месяц',nvlmoney2x(part_value_get(p_part,p_scode,5)))|| 
          xnode('СуммаПоследние3месяц',nvlmoney2x(part_value_get(p_part,p_scode,6))) 
       ) 
    end; 
end; 
begin 
  for pt in 
    (select column_value pname from table(parts_tbl) where column_value like part21_name||'%')  
  loop 
--dbms_output.put_line(i); 
    dbms_lob.append(p_cxml,'<'||l_p21tag||'>'); 
    dbms_lob.append(p_cxml, 
      xnode('КодТарифа' 
          ,substr('0'||regexp_replace(pt.pname,part21_name||'(*)','\1'),-2,2))|| 
      xnode(case when (v_pack.org.pyear*10 + v_pack.org.pindex) < 20152 
              then 'НаОбязательноеПенсионноеСтрахование2014' 
              else 'НаОбязательноеПенсионноеСтрахование' 
            end, 
          xnode('СуммаВыплатИвознагражденийОПС',part21_blk(200,pt.pname))|| 
          xnode('НеПодлежащиеОбложениюОПС',part21_blk(201,pt.pname))|| 
          xnode('СуммаРасходовПринимаемыхКвычетуОПС',part21_blk(202,pt.pname))|| 
          xnode('ПревышающиеПредельнуюВеличинуБазыОПС',part21_blk(203,pt.pname))|| 
          xnode('БазаДляНачисленияСтраховыхВзносовНаОПС',part21_blk(204,pt.pname))|| 
          xnode('НачисленоНаОПСсСуммНеПревышающих',part21_blk(205,pt.pname))|| 
          xnode('НачисленоНаОПСсСуммПревышающих',part21_blk(206,pt.pname))|| 
          xnode('КоличествоФЛвсего',part21_blk(207,pt.pname))|| 
          xnode('КоличествоФЛпоКоторымБазаПревысилаПредел',part21_blk(208,pt.pname)) 
    )); 
    dbms_lob.append(p_cxml, 
      xnode('НаОбязательноеМедицинскоеСтрахование', 
          xnode('СуммаВыплатИвознаграждений',part21_blk(210,pt.pname))|| 
          xnode('НеПодлежащиеОбложению',part21_blk(211,pt.pname))|| 
          xnode('СуммаРасходовПринимаемыхКвычету',part21_blk(212,pt.pname))|| 
          case when (v_pack.org.pyear*10+v_pack.org.pindex) < 20152  
          then 
             xnode('ПревышающиеПредельнуюВеличинуБазы',part21_blk(213,pt.pname))|| 
             xnode('БазаДляНачисленияСтраховыхВзносовНаОМС',part21_blk(214,pt.pname))|| 
             xnode('НачисленоНаОМС',part21_blk(215,pt.pname)) 
          else 
             xnode('БазаДляНачисленияСтраховыхВзносовНаОМС',part21_blk(213,pt.pname))|| 
             xnode('НачисленоНаОМС',part21_blk(214,pt.pname))|| 
             xnode('КоличествоФЛвсего',part21_blk(215,pt.pname)) 
          end 
    )); 
    dbms_lob.append(p_cxml,'</'||l_p21tag||'>'); 
  end loop; 
end; 
-- 
Procedure rsv_part1_append(p_cxml in out nocopy CLOB) 
as 
  l_p1tag constant varchar2(200):='Раздел1РасчетПоНачисленнымУплаченным2014'; 
Function part1_blk(p_scode number) return varchar2 
as 
begin 
  return   
    xnode('КодСтроки',p_scode)|| 
    xnode('СтраховыеВзносыОПС',nvlmoney2x(part_value_get(part1_name,p_scode,3)))|| 
    case when p_scode not in (110,111,112,113,114) 
      then 
        xnode('ОПСстраховаяЧасть',nvlmoney2x(part_value_get(part1_name,p_scode,4)))|| 
        xnode('ОПСнакопительнаяЧасть',nvlmoney2x(part_value_get(part1_name,p_scode,5)) 
            ,p_scode<>121) 
      else '' 
    end || 
    xnode('ВзносыПоДопТарифу1',nvlmoney2x(part_value_get(part1_name,p_scode,6)),p_scode<>121)|| 
    xnode('ВзносыПоДопТарифу2_18',nvlmoney2x(part_value_get(part1_name,p_scode,7)),p_scode<>121)|| 
    xnode('СтраховыеВзносыОМС',nvlmoney2x(part_value_get(part1_name,p_scode,8)),p_scode<>121); 
end; 
begin 
  dbms_lob.append(p_cxml,'<'||l_p1tag||'>'); 
  case when (v_pack.org.pyear*10 + v_pack.org.pindex) < 20152 
  then 
    dbms_lob.append(p_cxml, 
      xnode('ОстатокЗадолженностиНаНачалоРасчетногоПериода2014', part1_blk(100)) 
    ); 
    dbms_lob.append(p_cxml, 
      xnode('НачисленоСначалаРасчетногоПериода2014', 
        xnode('ВсегоСначалаРасчетногоПериода2014', part1_blk(110))|| 
        xnode('ПоследниеТриМесяца1с2014', part1_blk(111))|| 
        xnode('ПоследниеТриМесяца2с2014', part1_blk(112))|| 
        xnode('ПоследниеТриМесяца3с2014', part1_blk(113))|| 
        xnode('ПоследниеТриМесяцаИтого2014', part1_blk(114)) 
    ));       
    dbms_lob.append(p_cxml, 
      xnode('ДоначисленоСначалаРасчетногоПериода2014всего', part1_blk(120))); 
    dbms_lob.append(p_cxml, 
      xnode('ДоначисленоСначалаРасчетногоПериода2014превышающие', part1_blk(121))); 
    dbms_lob.append(p_cxml, 
      xnode('ВсегоКуплате2014', part1_blk(130))); 
    dbms_lob.append(p_cxml, 
      xnode('УплаченоСначалаРасчетногоПериода2014', 
        xnode('ВсегоСначалаРасчетногоПериода2014', part1_blk(140))|| 
        xnode('ПоследниеТриМесяца1с2014', part1_blk(141))|| 
        xnode('ПоследниеТриМесяца2с2014', part1_blk(142))|| 
        xnode('ПоследниеТриМесяца3с2014', part1_blk(143))|| 
        xnode('ПоследниеТриМесяцаИтого2014', part1_blk(144)) 
    )); 
    dbms_lob.append(p_cxml, 
      xnode('ОстатокЗадолженностиНаКонецРасчетногоПериода2014', part1_blk(150))); 
  else 
    dbms_lob.append(p_cxml, 
      xnode('ОстатокЗадолженностиНаНачалоРасчетногоПериода', part1_blk(100)) 
    ); 
    dbms_lob.append(p_cxml, 
      xnode('НачисленоСначалаРасчетногоПериода', 
        xnode('ВсегоСначалаРасчетногоПериода', part1_blk(110))|| 
        xnode('ПоследниеТриМесяца1', part1_blk(111))|| 
        xnode('ПоследниеТриМесяца2', part1_blk(112))|| 
        xnode('ПоследниеТриМесяца3', part1_blk(113))|| 
        xnode('ПоследниеТриМесяцаИтого', part1_blk(114)) 
    ));       
    dbms_lob.append(p_cxml, 
      xnode('ДоначисленоСначалаРасчетногоПериодаВсего', part1_blk(120))); 
    dbms_lob.append(p_cxml, 
      xnode('ДоначисленоСначалаРасчетногоПериодаПревышающие', part1_blk(121))); 
    dbms_lob.append(p_cxml, 
      xnode('ВсегоКуплате', part1_blk(130))); 
    dbms_lob.append(p_cxml, 
      xnode('УплаченоСначалаРасчетногоПериода', 
        xnode('ВсегоСначалаРасчетногоПериода', part1_blk(140))|| 
        xnode('ПоследниеТриМесяца1', part1_blk(141))|| 
        xnode('ПоследниеТриМесяца2', part1_blk(142))|| 
        xnode('ПоследниеТриМесяца3', part1_blk(143))|| 
        xnode('ПоследниеТриМесяцаИтого', part1_blk(144)) 
    )); 
    dbms_lob.append(p_cxml, 
      xnode('ОстатокЗадолженностиНаКонецРасчетногоПериода', part1_blk(150))); 
  end case; 
  dbms_lob.append(p_cxml,'</'||l_p1tag||'>'); 
  return; 
end; 
-- Генерация РСВ-1 
Function rsv_generate return clob 
as 
l_cxml CLOB; 
l_rtag varchar2(200):='РАСЧЕТ_ПО_СТРАХОВЫМ_ВЗНОСАМ_НА_ОПС_И_ОМС_ПЛАТЕЛЬЩИКАМИ_ПРОИЗВОДЯЩИМИ_ВЫПЛАТЫ_ФЛ_'; 
l_p2tag constant varchar2(200):='Раздел2РасчетПоТарифуИдопТарифу'; 
begin 
  if v_pack.org.pyear < 2014 then raise_error(4); end if; -- unsupported 
  if (v_pack.org.pyear * 10) + v_pack.org.pindex > 20151 then 
    l_rtag := l_rtag || '2015'; 
  else 
    l_rtag := l_rtag || '2014';  
  end if; 
  dbms_lob.createtemporary(l_cxml, true, dbms_lob.session); 
  if v_pack.files.count=0 then return l_cxml; end if; 
  l_cxml:='<?xml version="1.0" encoding="Windows-1251" ?><ФайлПФР xmlns="http://schema.pfr.ru">'|| 
    xnode('ИмяФайла', file_name_make(0))|| 
--    xnode('ИмяФайла', file_name_make(v_pack.files.last+1))|| 
--    xnode('ИмяФайла', file_name_make(v_pack.files.first-1))|| 
    xnode('ЗаголовокФайла', 
        xnode('ВерсияФормата','07.00')|| 
        xnode('ТипФайла','ВНЕШНИЙ')|| 
        xnode('ПрограммаПодготовкиДанных', 
            xnode('НазваниеПрограммы',upper(c_program))|| 
            xnode('Версия',upper(c_version)) 
        )|| 
        xnode('ИсточникДанных','СТРАХОВАТЕЛЬ') 
    )||'<ПачкаВходящихДокументов Окружение="Единичный запрос" >'|| --Стадия="До обработки" 
    '<'||l_rtag||'>'|| 
    xnode('НомерВпачке',1)|| 
    xnode('РегистрационныйНомерПФР',num2pfn(v_pack.org.opfn))|| 
    xnode('НомерКорректировки','000')|| 
    xnode('КодОтчетногоПериода',pindex2x(v_pack.org.pindex,v_pack.org.pyear))|| 
    xnode('КалендарныйГод',v_pack.org.pyear)|| 
--    xnode('ПрекращениеДеятельности',null)|| 
    xnode('НаименованиеОрганизации',upper(v_pack.org.oname))|| 
    xnode('ИННсимвольный',v_pack.org.oinn)|| 
    xnode('КПП',v_pack.org.okpp)|| 
    xnode('КодПоОКВЭД',nvl(v_pack.org.okved,'80.30.1'))|| 
--    xnode('КодПоОКВЭД',nvl(part_value_get(fld_orgokved),'80.30.1'))|| 
    xnode('Телефон',null)|| 
    xnode('КоличествоЗЛ',part_value_get(fld_empcount))|| 
    xnode('СреднесписочнаяЧисленность',part_value_get(fld_empavg))|| 
    xnode('КоличествоСтраниц',1);--|| 
--    xnode('КоличествоЛистовПриложения',1); 
  rsv_part1_append(l_cxml); 
  dbms_lob.append(l_cxml,'<'||l_p2tag||'>'); 
  rsv_part21_append(l_cxml); 
  rsv_part25_append(l_cxml); 
  dbms_lob.append(l_cxml,'</'||l_p2tag||'>'); 
--  dbms_lob.append(l_cxml,'<Раздел3РасчетНаПравоПримененияПониженногоТарифа2014/>'); 
  rsv_part4_append(l_cxml); 
--  dbms_lob.append(l_cxml,'<Раздел5СведенияОВыплатахВпользуОбучающихся/>'); 
  dbms_lob.append(l_cxml, 
    xnode('ЛицоПодтверждающееСведения',1)|| 
    xnode('ФИОлицаПодтверждающегоСведения', 
      xnode('Фамилия','')|| 
      xnode('Имя','')|| 
      xnode('Отчество','')) 
  ); 
  dbms_lob.append(l_cxml,xnode('ДатаЗаполнения',date2x(sysdate))); 
  dbms_lob.append(l_cxml,'</'||l_rtag||'></ПачкаВходящихДокументов></ФайлПФР>'); 
  return l_cxml; 
end;
--
Function xml2blob
( p_xml XMLType
, p_csname varchar2 := 'CL8MSWIN1251'
, p_debug boolean := false)
return BLOB
is
  l_xml XMLType;
  c_xsl constant XMLType := XMLType(  
'<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
   <xsl:output  indent="no" omit-xml-declaration="no" standalone="yes"/>
   <xsl:template match="@*|node()">  
      <xsl:copy>  
        <xsl:apply-templates select="@*|node()"/>  
     </xsl:copy>  
   </xsl:template>  
</xsl:stylesheet>');  
begin
  if p_debug then return p_xml.getBlobVal(nls_charset_id(p_csname),0,2); end if;
-- удалить объявления ns из тегов
  select xmltransform(p_xml, c_xsl) into l_xml from dual;
  return l_xml.getBlobVal(nls_charset_id(p_csname),4,0);
end;
-- удалить default namespace из файлов ПФ 2010-2016гг
Function ns_remove(p_clob CLOB) return CLOB 
as 
begin 
  return replace( p_clob
                , regexp_substr(p_clob,'<ФайлПФР[ ]+xmlns[^>]+>',1,1,'i')
                , '<ФайлПФР>'); 
end; 
-- p_csname is null : кодировка из XML декларации
Function blob2xml(p_blob BLOB, p_csname Varchar2 := null) return XMLType
is
  l_xml XMLType;
  l_clob CLOB;
begin
  l_xml:= XMLType(p_blob
    , case when p_csname is null then null else nls_charset_id(p_csname) end );
  if (l_xml.getrootelement() = 'ФайлПФР'
       and l_xml.getnamespace() = 'http://schema.pfr.ru')
  then
    l_clob:= blob2clob(p_blob);
    l_xml := XMLType(ns_remove(l_clob));
    if dbms_lob.istemporary(l_clob) = 1 
    then dbms_lob.freetemporary(l_clob); end if;
  end if;
  return l_xml;
end;
-- Преобразования BLOB <-> CLOB (encoding="windows-1251")
Function blob2clob(p_blob BLOB, p_csname varchar2:='CL8MSWIN1251') return CLOB 
is 
  c_lob_maxsize number := DBMS_LOB.LOBMAXSIZE; 
  c_lang_context  integer := DBMS_LOB.DEFAULT_LANG_CTX; 
  c_warning       integer := DBMS_LOB.WARN_INCONVERTIBLE_CHAR; 
  c_start_blob number := 1; 
  c_start_clob number := 1; 
  l_clob CLOB;
begin 
  dbms_lob.createtemporary(l_clob, TRUE, dbms_lob.session); 
  DBMS_LOB.CONVERTTOCLOB 
  ( dest_lob    =>l_clob 
  , src_blob    =>p_blob 
  , amount      =>c_lob_maxsize 
  , dest_offset =>c_start_clob 
  , src_offset  =>c_start_blob 
  , blob_csid   =>nls_charset_id(p_csname) 
  , lang_context=>c_lang_context 
  , warning     =>c_warning 
  ); 
return l_clob; 
end; 
-- 
Function clob2blob(p_clob in CLOB, p_csname varchar2:='CL8MSWIN1251') return BLOB 
is 
  c_lob_maxsize number := DBMS_LOB.LOBMAXSIZE; 
  c_lang_context  integer := DBMS_LOB.DEFAULT_LANG_CTX; 
  c_warning       integer := DBMS_LOB.WARN_INCONVERTIBLE_CHAR; 
  c_start_blob number := 1; 
  c_start_clob number := 1; 
  l_blob BLOB; 
begin 
  dbms_lob.createtemporary(l_blob, TRUE, dbms_lob.session); 
  DBMS_LOB.CONVERTTOBLOB 
    ( dest_lob    =>l_blob 
    , src_clob    =>p_clob 
    , amount      =>c_lob_maxsize 
    , dest_offset =>c_start_blob 
    , src_offset  =>c_start_clob 
    , blob_csid   =>nls_charset_id(p_csname) 
    , lang_context=>c_lang_context 
    , warning     =>c_warning 
    ); 
return l_blob; 
end; 
-- Инициализация пакета 
begin 
  c_abbr('ИСХ'):='ИСХОДНАЯ'; 
  c_abbr('КОР'):='КОРРЕКТИРУЮЩАЯ'; 
  c_abbr('ОТМ'):='ОТМЕНЯЮЩАЯ'; 
  c_abbr('ТРУ'):='ТРУДОВОЙ'; 
  c_abbr('ГРА'):='ГРАЖДАНСКО-ПРАВОВОЙ'; 
  c_abbr('1'):='СЗВ-6-1'; 
  c_abbr('2'):='СЗВ-6-2'; 
  c_abbr('3'):='СЗВ-6-3'; 
  c_abbr('4'):='СЗВ-6-4'; 
  c_abbr('5'):='СЗВ-РСВ'; 
  c_abbr('8'):='АДВ'; 
  c_abbr('9'):='РСВ-1'; 
  c_abbr('СЗВ-6-1'):='1'; 
  c_abbr('СЗВ-6-2'):='2'; 
end "PF_XML6"; 
/
